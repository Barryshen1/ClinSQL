WITH male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 83 AND 93
),
acs_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    CASE
      WHEN TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN male_patients mp ON adm.subject_id = mp.subject_id
  WHERE TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
),
acs_diagnoses AS (
  SELECT
    da.subject_id,
    da.hadm_id,
    CASE WHEN di.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN acs_admissions da ON di.subject_id = da.subject_id AND di.hadm_id = da.hadm_id
  WHERE (
    (di.icd_version = 10 AND (
      LEFT(di.icd_code, 3) IN ('I20', 'I21', 'I22', 'I24')
    ))
    OR
    (di.icd_version = 9 AND (
      LEFT(di.icd_code, 3) IN ('410', '411', '412', '413', '414')
    ))
  )
),
ultrasound_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%ultrasound%'
  GROUP BY p.subject_id, p.hadm_id
),
admission_ultrasound_counts AS (
  SELECT
    aa.subject_id,
    aa.hadm_id,
    aa.los_group,
    ad.diagnosis_type,
    COALESCE(up.ultrasound_count, 0) AS ultrasound_count
  FROM acs_admissions aa
  INNER JOIN acs_diagnoses ad
    ON aa.subject_id = ad.subject_id AND aa.hadm_id = ad.hadm_id
  LEFT JOIN ultrasound_procedures up
    ON aa.subject_id = up.subject_id AND aa.hadm_id = up.hadm_id
  WHERE aa.los_group IS NOT NULL
)
SELECT
  los_group,
  diagnosis_type,
  AVG(ultrasound_count) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM admission_ultrasound_counts
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;