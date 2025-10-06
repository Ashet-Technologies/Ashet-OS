
use addr2line::Loader;

pub struct Lookup {
    loader: Loader
}

#[repr(C)]
pub struct OutString {
    ptr: *mut u8,
    len: usize,
    capacity: usize,
}


#[repr(C)]
pub struct Location {
    file: OutString,
    line: u32,
    column: u32,
}

#[unsafe(no_mangle)]
pub extern "C" fn lookup_create(path_ptr: *const u8, path_len: usize) -> *mut Lookup {

    let path = unsafe {
        str::from_utf8_unchecked(std::slice::from_raw_parts(path_ptr, path_len))
    };

    let loader = Loader::new(path).unwrap();

    let lookup = Lookup {
        loader: loader 
    };

    Box::into_raw(Box::new(lookup))
}


#[unsafe(no_mangle)]
pub extern "C" fn lookup_destroy(ptr: *mut Lookup) {
    _ = unsafe { Box::from_raw(ptr) };
}



#[unsafe(no_mangle)]
pub extern "C" fn lookup_location(ptr: *mut Lookup, result_ptr: *mut Location, addr: u64 ) -> bool {

    let lookup: &Lookup = unsafe { &*ptr };

    let maybe_location = lookup.loader.find_location(addr).unwrap();

    let location = match maybe_location {
        Some(location) => location,
        None => return false,
    };

    let result: &mut Location = unsafe { &mut * result_ptr };

    match location.file {
        Some(path) => {
            if ! result.file.set(path) {
                return false 
            }
        }
        None => {
            result.file.len = 0
        }
    }

    result.line = location.line.unwrap_or(0);
    result.column = location.column.unwrap_or(0);

    true 
}   
#[unsafe(no_mangle)]
pub extern "C" fn lookup_symbol(ptr: *mut Lookup, result_ptr: *mut OutString, addr: u64 ) -> bool {

    let lookup: &Lookup = unsafe { &*ptr };

    let maybe_sym = lookup.loader.find_symbol(addr);

    let sym = match maybe_sym{
        Some(sym) => sym,
        None => return false,
    };

    
    let result: &mut OutString = unsafe { &mut * result_ptr };
    
    result.set(sym)
}   

impl OutString {
    fn set(&mut self, text: &str) -> bool {
        let dst = unsafe {
            std::slice::from_raw_parts_mut(self.ptr, self.capacity)
        };
        let src: &[u8] = text.as_ref();
        let len = src.len();

        if len > dst.len() {
            return false;
        }

        dst[0..len].copy_from_slice(src);
        self.len = len;

        true 
    }
}