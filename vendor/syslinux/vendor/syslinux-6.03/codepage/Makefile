VPATH		= $(SRC)
PERL		= perl
CPSRC		= $(wildcard $(SRC)/*.txt)
CPOBJ		= $(notdir $(CPSRC))
GENFILES	= $(patsubst %.txt,%.cp,$(CPOBJ))

.SUFFIXES: .txt .cp

all: $(GENFILES)

# This generates codepage files where the display and filesystem
# codepages are both the same.
%.cp: %.txt cptable.pl UnicodeData
	$(PERL) $(SRC)/cptable.pl $(SRC)/UnicodeData $< $< $@

tidy:
	rm -f *.cp *.bin

clean: tidy

dist: tidy

spotless: clean
