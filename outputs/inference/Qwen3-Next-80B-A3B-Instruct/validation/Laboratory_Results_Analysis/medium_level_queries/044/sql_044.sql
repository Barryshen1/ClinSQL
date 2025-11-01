WITH initial_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS troponin_t_value,
    l.charttime,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM 
    physionet-data.mimiciv_3_1_hosp.labevents l
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE 
    d.label = 'Troponin-T'
    AND l.valueuom = 'ng/mL'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0.01
),
filtered_admissions AS (
  SELECT 
    it.hadm_id,
    it.troponin_t_value
  FROM 
    initial_troponin it
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON it.hadm_id = a.hadm_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE 
    it.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
)
SELECT 
  COUNT(*) AS n,
  AVG(troponin_t_value) AS mean,
  STDDEV_SAMP(troponin_t_value) AS sd,
  MIN(troponin_t_value) AS min,
  MAX(troponin_t_value) AS max,
  APPROX_QUANTILES(troponin_t_value, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(troponin_t_value, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(troponin_t_value, 100)[OFFSET(75)] AS p75
FROM 
  filtered_admissions;