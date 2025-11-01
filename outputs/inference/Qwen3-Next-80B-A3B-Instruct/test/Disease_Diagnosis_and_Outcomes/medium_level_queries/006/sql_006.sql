WITH sepsis_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    i.los
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND i.intime = (
      SELECT MIN(intime)
      FROM physionet-data.mimiciv_3_1_icu.icustays i2
      WHERE i2.hadm_id = a.hadm_id
    )
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('995.92'))
          OR (d.icd_version = 10 AND d.icd_code IN ('A41.9', 'A41.51', 'A41.52', 'A41.81', 'A41.89', 'A41.9'))
        )
    )
    AND NOT EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code = '785.52')
          OR (d.icd_version = 10 AND d.icd_code = 'R65.21')
        )
    )
),
ckd_diabetes_flags AS (
  SELECT
    d.hadm_id,
    MAX(CASE
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '585%')
        OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%')
      THEN 1 ELSE 0 END) AS ckd_flag,
    MAX(CASE
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%')
        OR (d.icd_version = 10 AND d.icd_code IN ('E10%', 'E11%', 'E13%', 'E14%'))
      THEN 1 ELSE 0 END) AS diabetes_flag
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  GROUP BY d.hadm_id
),
final_data AS (
  SELECT
    sp.subject_id,
    sp.hadm_id,
    sp.hospital_expire_flag,
    sp.los,
    cdf.ckd_flag,
    cdf.diabetes_flag,
    NTILE(4) OVER (ORDER BY sp.los) AS los_quartile
  FROM sepsis_patients sp
  LEFT JOIN ckd_diabetes_flags cdf
    ON sp.hadm_id = cdf.hadm_id
)
SELECT
  los_quartile,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(ckd_flag) AS ckd_prevalence,
  AVG(diabetes_flag) AS diabetes_prevalence
FROM final_data
GROUP BY los_quartile
ORDER BY los_quartile;