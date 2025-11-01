WITH primary_upper_gi_admissions AS (
  SELECT
    a.hadm_id,
    -- LOS in days as a floating value (fractional days)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND d.seq_num = 1  -- primary diagnosis
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
    -- match common textual descriptions for upper GI bleeding
    AND REGEXP_CONTAINS(dd.long_title, r'(?i)(upper|hematemesis|melena|gastrointestinal hemorrhag|gastrointestinal bleed|gi hemorrhag)')
  GROUP BY a.hadm_id, los_days
)

SELECT
  COUNT(*) AS n_admissions,
  AVG(los_days) AS mean_los_days,
  STDDEV_SAMP(los_days) AS sd_los_days
FROM primary_upper_gi_admissions;