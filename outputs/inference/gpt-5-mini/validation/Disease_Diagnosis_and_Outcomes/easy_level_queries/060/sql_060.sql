WITH filtered_adm AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON a.hadm_id = dx.hadm_id AND a.subject_id = dx.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON dx.icd_code = dicd.icd_code AND dx.icd_version = dicd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND dx.seq_num = 1  -- primary diagnosis
    AND dicd.long_title IS NOT NULL
    AND (
      LOWER(dicd.long_title) LIKE '%upper gastrointestinal%' OR
      LOWER(dicd.long_title) LIKE '%upper gi%' OR
      LOWER(dicd.long_title) LIKE '%gastrointestinal hemorrhage%' OR
      LOWER(dicd.long_title) LIKE '%gastrointestinal haemorrhage%' OR
      LOWER(dicd.long_title) LIKE '%gi hemorrhage%' OR
      LOWER(dicd.long_title) LIKE '%gi haemorrhage%' OR
      LOWER(dicd.long_title) LIKE '%gastrointestinal bleed%' OR
      LOWER(dicd.long_title) LIKE '%gi bleed%' OR
      LOWER(dicd.long_title) LIKE '%hematemesis%' OR
      LOWER(dicd.long_title) LIKE '%melena%' OR
      LOWER(dicd.long_title) LIKE '%peptic ulcer with hemorrhage%' OR
      LOWER(dicd.long_title) LIKE '%peptic ulcer with haemorrhage%' OR
      LOWER(dicd.long_title) LIKE '%ulcer with hemorrhage%' OR
      LOWER(dicd.long_title) LIKE '%gastric ulcer with hemorrhage%' OR
      LOWER(dicd.long_title) LIKE '%duodenal ulcer with hemorrhage%' OR
      LOWER(dicd.long_title) LIKE '%hemorrhage of gastrointestinal tract%' OR
      LOWER(dicd.long_title) LIKE '%haemorrhage of gastrointestinal tract%'
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) >= 0
)
SELECT
  COUNT(*) AS n_admissions,
  -- APPROX_QUANTILES returns an array indexed 0..100; OFFSET(25) is the 25th percentile
  (SELECT APPROX_QUANTILES(los_days, 100)[OFFSET(25)] FROM filtered_adm) AS p25_los_days
FROM filtered_adm;