CASE 
    WHEN l.ref_range_upper IS NOT NULL AND valuenum <= l.ref_range_upper THEN 'Normal'
    WHEN l.ref_range_lower IS NOT NULL AND valuenum > l.ref_range_upper AND valuenum <= l.ref_range_lower THEN 'Borderline'
    WHEN valuenum > COALESCE(l.ref_range_lower, 0.03) THEN 'Elevated'
    ELSE 'Unknown'
  END;