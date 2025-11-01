WITH sepsis_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    ROUND(TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0, 2) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
    AND dx.seq_num = 1 -- primary diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
    ON dx.icd_code = ddx.icd_code
    AND dx.icd_version = ddx.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 67 AND 77
    AND adm.dischtime IS NOT NULL
    AND (
      LOWER(ddx.long_title) LIKE '%sepsis%'
      OR LOWER(ddx.long_title) LIKE '%septic shock%'
    )
)
SELECT
  STDDEV_SAMP(los_days) AS sd_los_days
FROM sepsis_admissions;