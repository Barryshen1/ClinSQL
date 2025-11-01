WITH male_pneumonia_admissions AS (
  SELECT 
    adm.hadm_id,
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
        ON diag.icd_code = d_diag.icd_code 
        AND diag.icd_version = d_diag.icd_version
      WHERE diag.hadm_id = adm.hadm_id
        AND LOWER(d_diag.long_title) LIKE '%pneumonia%'
    )
),
glucose_at_discharge AS (
  SELECT 
    le.valuenum AS glucose_value
  FROM male_pneumonia_admissions mpa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON mpa.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE 
    dli.fluid = 'Blood'
    AND LOWER(dli.label) LIKE '%glucose%'
    AND le.charttime <= mpa.dischtime
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY mpa.hadm_id 
    ORDER BY le.charttime DESC
  ) = 1
)
SELECT 
  PERCENTILE_CONT(glucose_value, 0.75) OVER() AS p75_glucose
FROM glucose_at_discharge
LIMIT 1;