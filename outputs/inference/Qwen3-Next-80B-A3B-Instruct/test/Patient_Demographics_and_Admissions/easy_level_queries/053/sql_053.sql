WITH target_patients AS (
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 52 AND 62
),
aki_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN target_patients tp ON a.subject_id = tp.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON a.hadm_id = di.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE LOWER(did.long_title) LIKE '%acute kidney injury%'
     OR LOWER(did.long_title) LIKE '%acute renal failure%'
     OR di.icd_code IN ('N17.0', 'N17.1', 'N17.2', 'N17.8', 'N17.9', 'N16.0', 'N16.1', 'N16.2', 'N16.8', 'N16.9')
),
readmission_flags AS (
  SELECT 
    aa.hadm_id,
    CASE 
      WHEN a2.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmission_30d
  FROM aki_admissions aa
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.admissions a2
    ON aa.subject_id = a2.subject_id
    AND a2.hadm_id != aa.hadm_id
    AND a2.admittime >= aa.dischtime
    AND a2.admittime <= DATE_ADD(aa.dischtime, INTERVAL 30 DAY)
)
SELECT 
  STDDEV(readmission_30d) AS per_encounter_stddev_30day_readmission
FROM readmission_flags;