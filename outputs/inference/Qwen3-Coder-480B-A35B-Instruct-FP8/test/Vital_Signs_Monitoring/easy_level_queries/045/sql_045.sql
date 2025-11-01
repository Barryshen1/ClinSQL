WITH first_rr AS (
  SELECT 
    ce.stay_id,
    MIN(ce.valuenum) AS first_rr_value -- Using MIN to get one value in case of duplicates at same charttime
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays AS icu
  JOIN 
    physionet-data.mimiciv_3_1_hosp.patients AS pat
    ON icu.subject_id = pat.subject_id
  JOIN 
    physionet-data.mimiciv_3_1_icu.chartevents AS ce
    ON icu.stay_id = ce.stay_id
  JOIN 
    physionet-data.mimiciv_3_1_icu.d_items AS di
    ON ce.itemid = di.itemid
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 51 AND 61
    AND LOWER(di.label) LIKE '%respiratory rate%'
    AND ce.valuenum IS NOT NULL
  GROUP BY 
    ce.stay_id
)

SELECT 
  STDDEV(first_rr_value) AS stddev_first_rr
FROM 
  first_rr;