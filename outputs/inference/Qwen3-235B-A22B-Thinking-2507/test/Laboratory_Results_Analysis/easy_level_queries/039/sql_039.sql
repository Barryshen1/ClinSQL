WITH male_pneumonia_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND (
            d.icd_code LIKE '480%' OR 
            d.icd_code LIKE '481%' OR 
            d.icd_code LIKE '482%' OR 
            d.icd_code LIKE '483%' OR 
            d.icd_code LIKE '484%' OR 
            d.icd_code LIKE '485%' OR 
            d.icd_code LIKE '486%' OR 
            d.icd_code LIKE '4870%'
          ))
          OR
          (d.icd_version = 10 AND (
            d.icd_code LIKE 'J12%' OR 
            d.icd_code LIKE 'J13%' OR 
            d.icd_code LIKE 'J14%' OR 
            d.icd_code LIKE 'J15%' OR 
            d.icd_code LIKE 'J16%' OR 
            d.icd_code LIKE 'J17%' OR 
            d.icd_code LIKE 'J18%'
          ))
        )
    )
),
creatinine_peaks AS (
  SELECT 
    l.hadm_id,
    MAX(l.valuenum) AS peak_creat
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN male_pneumonia_admissions m
    ON l.hadm_id = m.hadm_id
  WHERE l.itemid = 50912  -- Serum creatinine itemid
    AND l.valuenum IS NOT NULL
  GROUP BY l.hadm_id
)
SELECT STDDEV(peak_creat) AS std_peak_creat
FROM creatinine_peaks;