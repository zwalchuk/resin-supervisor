Promise = require 'bluebird'
_ = require 'lodash'
m = require 'mochainon'

{ stub } = m.sinon
m.chai.use(require('chai-events'))
{ expect } = m.chai

prepare = require './lib/prepare'
DeviceState = require '../src/device-state'
DB = require('../src/db')
Config = require('../src/config')

Service = require '../src/compose/service'

mockedInitialConfig = {
	'RESIN_HOST_LOG_TO_DISPLAY': '1'
	'RESIN_SUPERVISOR_CONNECTIVITY_CHECK': 'true'
	'RESIN_SUPERVISOR_DELTA': 'false'
	'RESIN_SUPERVISOR_DELTA_APPLY_TIMEOUT': ''
	'RESIN_SUPERVISOR_DELTA_REQUEST_TIMEOUT': ''
	'RESIN_SUPERVISOR_DELTA_RETRY_COUNT': ''
	'RESIN_SUPERVISOR_DELTA_RETRY_INTERVAL': ''
	'RESIN_SUPERVISOR_LOCAL_MODE': 'false'
	'RESIN_SUPERVISOR_LOG_CONTROL': 'true'
	'RESIN_SUPERVISOR_OVERRIDE_LOCK': 'false'
	'RESIN_SUPERVISOR_POLL_INTERVAL': '60000'
	'RESIN_SUPERVISOR_VPN_CONTROL': 'true'
}

testTarget1 = {
	local: {
		name: 'aDevice'
		config: {
			'RESIN_HOST_CONFIG_gpu_mem': '256'
			'RESIN_HOST_LOG_TO_DISPLAY': '0'
			'RESIN_SUPERVISOR_CONNECTIVITY_CHECK': 'true'
			'RESIN_SUPERVISOR_DELTA': 'false'
			'RESIN_SUPERVISOR_DELTA_APPLY_TIMEOUT': ''
			'RESIN_SUPERVISOR_DELTA_REQUEST_TIMEOUT': ''
			'RESIN_SUPERVISOR_DELTA_RETRY_COUNT': ''
			'RESIN_SUPERVISOR_DELTA_RETRY_INTERVAL': ''
			'RESIN_SUPERVISOR_LOCAL_MODE': 'false'
			'RESIN_SUPERVISOR_LOG_CONTROL': 'true'
			'RESIN_SUPERVISOR_OVERRIDE_LOCK': 'false'
			'RESIN_SUPERVISOR_POLL_INTERVAL': '60000'
			'RESIN_SUPERVISOR_VPN_CONTROL': 'true'
		}
		apps: {
			'1234': {
				appId: 1234
				name: 'superapp'
				commit: 'abcdef'
				releaseId: 1
				services: [
					{
						appId: 1234
						serviceId: 23
						imageId: 12345
						serviceName: 'someservice'
						releaseId: 1
						image: 'registry2.resin.io/superapp/abcdef:latest'
						labels: {
							'io.resin.something': 'bar'
						}
					}
				]
				volumes: {}
				networks: {}
			}
		}
	}
	dependent: { apps: [], devices: [] }
}

testTarget2 = {
	local: {
		name: 'aDeviceWithDifferentName'
		config: {
			'RESIN_HOST_CONFIG_gpu_mem': '512'
			'RESIN_HOST_LOG_TO_DISPLAY': '1'
		}
		apps: {
			'1234': {
				name: 'superapp'
				commit: 'afafafa'
				releaseId: 2
				services: {
					'23': {
						serviceName: 'aservice'
						imageId: 12345
						image: 'registry2.resin.io/superapp/edfabc'
						environment: {
							'FOO': 'bar'
						}
						labels: {}
					},
					'24': {
						serviceName: 'anotherService'
						imageId: 12346
						image: 'registry2.resin.io/superapp/afaff'
						environment: {
							'FOO': 'bro'
						}
						labels: {}
					}
				}
			}
		}
	}
	dependent: { apps: [], devices: [] }
}
testTargetWithDefaults2 = {
	local: {
		name: 'aDeviceWithDifferentName'
		config: {
			'RESIN_HOST_CONFIG_gpu_mem': '512'
			'RESIN_HOST_LOG_TO_DISPLAY': '1'
			'RESIN_SUPERVISOR_CONNECTIVITY_CHECK': 'true'
			'RESIN_SUPERVISOR_DELTA': 'false'
			'RESIN_SUPERVISOR_DELTA_APPLY_TIMEOUT': ''
			'RESIN_SUPERVISOR_DELTA_REQUEST_TIMEOUT': ''
			'RESIN_SUPERVISOR_DELTA_RETRY_COUNT': ''
			'RESIN_SUPERVISOR_DELTA_RETRY_INTERVAL': ''
			'RESIN_SUPERVISOR_LOCAL_MODE': 'false'
			'RESIN_SUPERVISOR_LOG_CONTROL': 'true'
			'RESIN_SUPERVISOR_OVERRIDE_LOCK': 'false'
			'RESIN_SUPERVISOR_POLL_INTERVAL': '60000'
			'RESIN_SUPERVISOR_VPN_CONTROL': 'true'
		}
		apps: {
			'1234': {
				appId: 1234
				name: 'superapp'
				commit: 'afafafa'
				releaseId: 2
				services: [
					_.merge({ appId: 1234, serviceId: 23, releaseId: 2 }, _.clone(testTarget2.local.apps['1234'].services['23'])),
					_.merge({ appId: 1234, serviceId: 24, releaseId: 2 }, _.clone(testTarget2.local.apps['1234'].services['24']))
				]
				volumes: {}
				networks: {}
			}
		}
	}
	dependent: { apps: [], devices: [] }
}

testTargetInvalid = {
	local: {
		name: 'aDeviceWithDifferentName'
		config: {
			'RESIN_HOST_CONFIG_gpu_mem': '512'
			'RESIN_HOST_LOG_TO_DISPLAY': '1'
		}
		apps: [
			{
				appId: '1234'
				name: 'superapp'
				commit: 'afafafa'
				releaseId: '2'
				config: {}
				services: [
					{
						serviceId: '23'
						serviceName: 'aservice'
						imageId: '12345'
						image: 'registry2.resin.io/superapp/edfabc'
						config: {}
						environment: {
							' FOO': 'bar'
						}
						labels: {}
					},
					{
						serviceId: '24'
						serviceName: 'anotherService'
						imageId: '12346'
						image: 'registry2.resin.io/superapp/afaff'
						config: {}
						environment: {
							'FOO': 'bro'
						}
						labels: {}
					}
				]
			}
		]
	}
	dependent: { apps: [], devices: [] }
}

describe 'deviceState', ->
	before ->
		@timeout(5000)
		prepare()
		@db = new DB()
		@config = new Config({ @db })
		eventTracker = {
			track: console.log
		}
		stub(Service.prototype, 'extendEnvVars').callsFake (env) ->
			@environment['ADDITIONAL_ENV_VAR'] = 'foo'
			return @environment
		@deviceState = new DeviceState({ @db, @config, eventTracker })
		stub(@deviceState.applications.docker, 'getNetworkGateway').returns(Promise.resolve('172.17.0.1'))
		stub(@deviceState.applications.images, 'inspectByName').callsFake ->
			Promise.try ->
				err = new Error()
				err.statusCode = 404
				throw err
		@db.init()
		.then =>
			@config.init()

	after ->
		Service.prototype.extendEnvVars.restore()
		@deviceState.applications.docker.getNetworkGateway.restore()
		@deviceState.applications.images.inspectByName.restore()

	it 'loads a target state from an apps.json file and saves it as target state, then returns it', ->
		stub(@deviceState.applications.images, 'save').returns(Promise.resolve())
		stub(@deviceState.deviceConfig, 'getCurrent').returns(Promise.resolve(mockedInitialConfig))
		@deviceState.loadTargetFromFile(process.env.ROOT_MOUNTPOINT + '/apps.json')
		.then =>
			@deviceState.getTarget()
		.then (targetState) =>
			testTarget = _.cloneDeep(testTarget1)
			testTarget.local.apps['1234'].services = _.map testTarget.local.apps['1234'].services, (s) ->
				s.imageName = s.image
				return new Service(s)
			# We serialize and parse JSON to avoid checking fields that are functions or undefined
			expect(JSON.parse(JSON.stringify(targetState))).to.deep.equal(JSON.parse(JSON.stringify(testTarget)))
			@deviceState.applications.images.save.restore()
			@deviceState.deviceConfig.getCurrent.restore()

	it 'emits a change event when a new state is reported', ->
		@deviceState.reportCurrentState({ someStateDiff: 'someValue' })
		expect(@deviceState).to.emit('change')

	it 'returns the current state'

	it 'writes the target state to the db with some extra defaults', ->
		testTarget = _.cloneDeep(testTargetWithDefaults2)
		Promise.map testTarget.local.apps['1234'].services, (s) =>
			@deviceState.applications.images.normalise(s.image)
			.then (imageName) ->
				s.image = imageName
				s.imageName = imageName
				new Service(s)
		.then (services) =>
			testTarget.local.apps['1234'].services = services
			@deviceState.setTarget(testTarget2)
		.then =>
			@deviceState.getTarget()
		.then (target) ->
			expect(JSON.parse(JSON.stringify(target))).to.deep.equal(JSON.parse(JSON.stringify(testTarget)))

	it 'does not allow setting an invalid target state', ->
		promise = @deviceState.setTarget(testTargetInvalid)
		promise.catch(->)
		expect(promise).to.be.rejected

	it 'allows triggering applying the target state', (done) ->
		stub(@deviceState, 'applyTarget').returns(Promise.resolve())
		@deviceState.triggerApplyTarget({ force: true })
		expect(@deviceState.applyTarget).to.not.be.called
		setTimeout =>
			expect(@deviceState.applyTarget).to.be.calledWith({ force: true, initial: false })
			@deviceState.applyTarget.restore()
			done()
		, 5

	it 'applies the target state for device config'

	it 'applies the target state for applications'
