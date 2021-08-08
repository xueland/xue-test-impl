all:
	@ $(MAKE) debug

release:
	nimble --cc:clang build --define:danger --define:noSignalHandler --gc:arc --passC:-flto --passL:-flto

debug:
	nimble --cc:clang build --define:debug --gc:arc

clean:
	@ rm -r build
