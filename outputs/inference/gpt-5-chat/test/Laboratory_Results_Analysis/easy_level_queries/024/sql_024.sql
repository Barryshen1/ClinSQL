WITH sepsis_male_adm AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON di.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (
      -- ICD-9 sepsis codes
      (di.icd_version = 9 AND di.icd_code IN ('99591','99592','78552'))
      OR (di.icd_version = 10 AND (
            di.icd_code LIKE 'A40%' OR di.icd_code LIKE 'A41%'))
    )
),
platelet_labs AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%platelet%'
    AND le.valuenum IS NOT NULL
),
first_platelet_per_adm AS (
  SELECT t.subject_id, t.hadm_id, t.valuenum
  FROM (
    SELECT pl.*,
           ROW_NUMBER() OVER (PARTITION BY pl.subject_id, pl.hadm_id ORDER BY pl.charttime ASC) AS rn
    FROM platelet_labs pl
    JOIN sepsis_male_adm sma
      ON pl.subject_id = sma.subject_id
     AND pl.hadm_id = sma.hadm_id
  ) t
  WHERE rn = 1
)
SELECT STDDEV_SAMP(valuenum) AS sd_admission_platelet
FROM first_platelet_per_adm;