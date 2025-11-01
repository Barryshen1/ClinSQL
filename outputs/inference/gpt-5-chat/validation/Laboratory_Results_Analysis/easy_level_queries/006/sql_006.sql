WITH copd_patients AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age = 50
    AND (
      -- ICD-10 COPD
      (dx.icd_version = 10 AND (dx.icd_code LIKE 'J44%' ))
      -- ICD-9 COPD
      OR (dx.icd_version = 9 AND (
            dx.icd_code LIKE '491%' OR
            dx.icd_code LIKE '492%' OR
            dx.icd_code LIKE '496%'
          ))
    )
),
sodium_labs AS (
  SELECT le.subject_id, le.hadm_id, le.valuenum, le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON le.hadm_id = adm.hadm_id
  WHERE di.fluid = 'BLOOD'
    AND di.label = 'SODIUM'
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN adm.admittime AND adm.dischtime
),
nadir_per_hadm AS (
  SELECT c.subject_id,
         c.hadm_id,
         MIN(s.valuenum) AS nadir_sodium
  FROM copd_patients c
  JOIN sodium_labs s
    ON c.subject_id = s.subject_id
   AND c.hadm_id = s.hadm_id
  GROUP BY c.subject_id, c.hadm_id
)
SELECT STDDEV_SAMP(nadir_sodium) AS stddev_nadir_sodium
FROM nadir_per_hadm;