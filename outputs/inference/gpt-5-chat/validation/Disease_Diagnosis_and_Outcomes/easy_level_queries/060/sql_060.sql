WITH primary_upper_gi_bleed AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.subject_id = dx.subject_id
    AND adm.hadm_id = dx.hadm_id
    AND dx.seq_num = 1   -- primary diagnosis
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code
    AND dx.icd_version = dd.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 74 AND 84
    AND LOWER(dd.long_title) LIKE '%upper%gi%'
    AND adm.dischtime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER () AS los_25th_percentile_days
FROM
  primary_upper_gi_bleed;