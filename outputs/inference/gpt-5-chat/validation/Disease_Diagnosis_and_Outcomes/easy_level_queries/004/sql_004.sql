WITH primary_dka_hhs AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.subject_id = diag.subject_id
    AND adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 73 AND 83
    AND diag.seq_num = 1
    AND (
      -- ICD-9: DKA 25010–25013, HHS 25020–25023
      (diag.icd_version = 9 AND (
        (diag.icd_code BETWEEN '25010' AND '25013') OR
        (diag.icd_code BETWEEN '25020' AND '25023')
      ))
      -- ICD-10: DKA E101, E111, E131; HHS E100, E110, E130 (without decimal)
      OR (diag.icd_version = 10 AND (
        diag.icd_code IN ('E100','E101','E110','E111','E130','E131')
      ))
    )
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_p25_days
FROM primary_dka_hhs;