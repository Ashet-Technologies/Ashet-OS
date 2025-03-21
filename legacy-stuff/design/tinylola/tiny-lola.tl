# Tiny Lola
fn Sum(a, b) {
  return a + b;
}

fn Main() {
  while(true) {
    var array = Malloc(10);
    var i = 0;
    while(i < 10) {
      array[i] = Sum(0x30, i);
      i += 1;
    }

    Print(array);

    Free(array);
    
    var key = ReadKey();
    if(key == 0) {
      break;
    } else {
      continue;
    }
  }
}