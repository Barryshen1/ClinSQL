WITH target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 69 AND 79
),

admissions_with_diagnoses AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN target_patients tp ON a.subject_id = tp.subject_id
  WHERE a.hadm_id IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE d.long_title LIKE '%UGIB%' OR d.long_title LIKE '%upper gastrointestinal bleed%'
    GROUP BY hadm_id
    HAVING COUNT(*) >= 1
  )
  AND a.hadm_id IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE d.long_title LIKE '%COPD exacerbation%' OR d.long_title LIKE '%chronic obstructive pulmonary disease with acute exacerbation%'
    GROUP BY hadm_id
    HAVING COUNT(*) >= 1
  )
)

SELECT
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days
FROM admissions_with_diagnoses;