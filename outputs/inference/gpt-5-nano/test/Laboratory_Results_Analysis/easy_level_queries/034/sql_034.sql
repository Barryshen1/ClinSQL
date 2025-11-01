WITH heart_failure_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic
    ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age = 65
    AND LOWER(dic.long_title) LIKE '%heart failure%'
),
min_sodium_per_admission AS (
  SELECT le.hadm_id, MIN(le.valuenum) AS min_sodium
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE le.hadm_id IN (SELECT hadm_id FROM heart_failure_admissions)
    AND LOWER(dli.label) LIKE '%sodium%'
    AND LOWER(dli.label) LIKE '%serum%'
    AND le.valuenum IS NOT NULL
  GROUP BY le.hadm_id
)
SELECT MIN(min_sodium) AS min_serum_sodium_across_cohort
FROM min_sodium_per_admission;