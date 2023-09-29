#!/usr/bin/env python

import sys, re, getopt

class Menusystem:

   types = {"run"      : "OPT_RUN",
            "inactive" : "OPT_INACTIVE",
            "checkbox" : "OPT_CHECKBOX",
            "radiomenu": "OPT_RADIOMENU",
            "sep"      : "OPT_SEP",
            "invisible": "OPT_INVISIBLE",
            "radioitem": "OPT_RADIOITEM",
            "exitmenu" : "OPT_EXITMENU",
            "login"    : "login", # special type
            "submenu"  : "OPT_SUBMENU"}

   entry_init = { "item" : "",
                  "info" : "",
                  "data" : "",
                  "ipappend" : 0, # flag to send in case of PXELINUX
                  "helpid" : 65535, # 0xFFFF
                  "shortcut":"-1",
                  "state"  : 0, # initial state of checkboxes
                  "argsmenu": "", # name of menu containing arguments
                  "perms"  : "", # permission required to execute this entry
                  "_updated" : None, # has this dictionary been updated
                  "type" : "run" }

   menu_init = {  "title" : "",
                  "row" : "0xFF", # let system decide position
                  "col" : "0xFF",
                  "_updated" : None,
                  "name" : "" }

   system_init ={ "videomode" : "0xFF",
                  "title" : "Menu System",
                  "top" : "1",
                  "left" : "1" ,
                  "bot" : "21",
                  "right":"79",
                  "helpdir" : "/isolinux/help",
                  "pwdfile" : "",
                  "pwdrow"  : "23",
                  "editrow" : "23",
                  "skipcondn"  : "0",
                  "skipcmd" : ".exit",
                  "startfile": "",
                  "onerrorcmd":".repeat",
                  "exitcmd"  : ".exit",
                  "exitcmdroot"  : "",
                  "timeout"  : "600",
                  "timeoutcmd":".beep",
                  "totaltimeout" : "0",
                  "totaltimeoutcmd" : ".wait"
                 }

   shift_flags = { "alt"  : "ALT_PRESSED",
                   "ctrl" : "CTRL_PRESSED",
                   "shift": "SHIFT_PRESSED",
                   "caps" : "CAPSLOCK_ON",
                   "num"  : "NUMLOCK_ON",
                   "ins"  : "INSERT_ON"
                 }

   reqd_templates = ["item","login","menu","system"]

   def __init__(self,template):
       self.state = "system"
       self.code_template_filename = template
       self.menus = []
       self.init_entry()
       self.init_menu()
       self.init_system()
       self.vtypes = " OR ".join(list(self.types.keys()))
       self.vattrs = " OR ".join([x for x in list(self.entry.keys()) if x[0] != "_"])
       self.mattrs = " OR ".join([x for x in list(self.menu.keys()) if x[0] != "_"])

   def init_entry(self):
       self.entry = self.entry_init.copy()

   def init_menu(self):
       self.menu = self.menu_init.copy()

   def init_system(self):
       self.system = self.system_init.copy()

   def add_menu(self,name):
       self.add_item()
       self.init_menu()
       self.menu["name"] = name
       self.menu["_updated"] = 1
       self.menus.append( (self.menu,[]) )

   def add_item(self):
       if self.menu["_updated"]: # menu details have changed
          self.menus[-1][0].update(self.menu)
          self.init_menu()
       if self.entry["_updated"]:
          if not self.entry["info"]:
             self.entry["info"] = self.entry["data"]
          if not self.menus:
             print("Error before line %d" % self.lineno)
             print("REASON: menu must be declared before a menu item is declared")
             sys.exit(1)
          self.menus[-1][1].append(self.entry)
       self.init_entry()

   def set_item(self,name,value):
       if name not in self.entry:
          msg = ["Unknown attribute %s in line %d" % (name,self.lineno)]
          msg.append("REASON: Attribute must be one of %s" % self.vattrs)
          return "\n".join(msg)
       if name=="type" and value not in self.types:
          msg = [ "Unrecognized type %s in line %d" % (value,self.lineno)]
          msg.append("REASON: Valid types are %s" % self.vtypes)
          return "\n".join(msg)
       if name=="shortcut":
          if (value != "-1") and not re.match("^[A-Za-z0-9]$",value):
             msg = [ "Invalid shortcut char '%s' in line %d" % (value,self.lineno) ]
             msg.append("REASON: Valid values are [A-Za-z0-9]")
             return "\n".join(msg)
          elif value != "-1": value = "'%s'" % value
       elif name in ["state","helpid","ipappend"]:
          try:
              value = int(value)
          except:
              return "Value of %s in line %d must be an integer" % (name,self.lineno)
       self.entry[name] = value
       self.entry["_updated"] = 1
       return ""

   def set_menu(self,name,value):
       if name not in self.menu:
          return "Error: Unknown keyword %s" % name
       self.menu[name] = value
       self.menu["_updated"] = 1
       return ""

   def set_system(self,name,value):
       if name not in self.system:
          return "Error: Unknown keyword %s" % name
       if name == "skipcondn":
          try: # is skipcondn a number?
             a = int(value)
          except: # it is a "-" delimited sequence
             value = value.lower()
             parts = [ self.shift_flags.get(x.strip(),None) for x in value.split("-") ]
             self.system["skipcondn"] = " | ".join([_f for _f in parts if _f])
       else:
          self.system[name] = value

   def set(self,name,value):
       # remove quotes if given
       if (value[0] == value[-1]) and (value[0] in ['"',"'"]): # remove quotes
          value = value[1:-1]
       if self.state == "system":
          err = self.set_system(name,value)
          if not err: return
       if self.state == "menu":
          err = self.set_menu(name,value)
          # change state to entry it menu returns error
          if err:
             err = None
             self.state = "item"
       if self.state == "item":
          err = self.set_item(name,value)

       if not err: return

       # all errors so return item's error message
       print(err)
       sys.exit(1)

   def print_entry(self,entry,fd):
       entry["type"] = self.types[entry["type"]]
       if entry["type"] == "login": #special type
          fd.write(self.templates["login"] % entry)
       else:
          fd.write(self.templates["item"] % entry)

   def print_menu(self,menu,fd):
       if menu["name"] == "main": self.foundmain = 1
       fd.write(self.templates["menu"] % menu)
       if (menu["row"] != "0xFF") or (menu["col"] != "0xFF"):
          fd.write('  set_menu_pos(%(row)s,%(col)s);\n' % menu)


   def output(self,filename):
       curr_template = None
       contents = []
       self.templates = {}
       regbeg = re.compile(r"^--(?P<name>[a-z]+) BEGINS?--\n$")
       regend = re.compile(r"^--[a-z]+ ENDS?--\n$")
       ifd = open(self.code_template_filename,"r")
       for line in ifd.readlines():
           b = regbeg.match(line)
           e = regend.match(line)
           if e: # end of template
              if curr_template:
                 self.templates[curr_template] = "".join(contents)
              curr_template = None
              continue
           if b:
              curr_template = b.group("name")
              contents = []
              continue
           if not curr_template: continue # lines between templates are ignored
           contents.append(line)
       ifd.close()

       missing = None
       for x in self.reqd_templates:
           if x not in self.templates: missing = x
       if missing:
           print("Template %s required but not defined in %s" % (missing,self.code_template_filename))

       if filename == "-":
          fd = sys.stdout
       else: fd = open(filename,"w")
       self.foundmain = None
       fd.write(self.templates["header"])
       fd.write(self.templates["system"] % self.system)
       for (menu,items) in self.menus:
           self.print_menu(menu,fd)
           for entry in items: self.print_entry(entry,fd)
       fd.write(self.templates["footer"])
       fd.close()
       if not self.foundmain:
          print("main menu not found")
          print(self.menus)
          sys.exit(1)

   def input(self,filename):
       if filename == "-":
          fd = sys.stdin
       else: fd = open(filename,"r")
       self.lineno = 0
       self.state = "system"
       for line in fd.readlines():
         self.lineno = self.lineno + 1
         if line and line[-1] in ["\r","\n"]: line = line[:-1]
         if line and line[-1] in ["\r","\n"]: line = line[:-1]
         line = line.strip()
         if line and line[0] in ["#",";"]: continue

         try:
           # blank line -> starting a new entry
           if not line:
              if self.state == "item": self.add_item()
              continue

           # starting a new section?
           if line[0] == "[" and line[-1] == "]":
              self.state = "menu"
              self.add_menu(line[1:-1])
              continue

           # add property of current entry
           pos = line.find("=") # find the first = in string
           if pos < 0:
              print("Syntax error in line %d" % self.lineno)
              print("REASON: non-section lines must be of the form ATTRIBUTE=VALUE")
              sys.exit(1)
           attr = line[:pos].strip().lower()
           value = line[pos+1:].strip()
           self.set(attr,value)
         except:
            print("Error while parsing line %d: %s" % (self.lineno,line))
            raise
       fd.close()
       self.add_item()

def usage():
    print(sys.argv[0]," [options]")
    print("--input=<file>    is the name of the .menu file declaring the menu structure")
    print("--output=<file>   is the name of generated C source")
    print("--template=<file> is the name of template to be used")
    print()
    print("input and output default to - (stdin and stdout respectively)")
    print("template defaults to adv_menu.tpl")
    sys.exit(1)

def main():
    tfile = "adv_menu.tpl"
    ifile = "-"
    ofile = "-"
    opts,args = getopt.getopt(sys.argv[1:], "hi:o:t:",["input=","output=","template=","help"])
    if args:
       print("Unknown options %s" % args)
       usage()
    for o,a in opts:
        if o in ["-i","--input"]:
           ifile = a
        elif o in ["-o", "--output"]:
           ofile = a
        elif o in ["-t","--template"]:
           tfile = a
        elif o in ["-h","--help"]:
           usage()

    inst = Menusystem(tfile)
    inst.input(ifile)
    inst.output(ofile)

if __name__ == "__main__":
   main()
