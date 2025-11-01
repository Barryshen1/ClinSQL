WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    CASE
      -- stay_bucket: 1-4 days vs 5-7 days
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS stay_bucket,
    CASE
      -- ED_Urgent vs Elective
      WHEN a.admission_type IN ('EMERGENCY','URGENT') THEN 'ED_Urgent'
      WHEN a.admission_type = 'ELECTIVE' THEN 'Elective'
      ELSE NULL
    END AS ed_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '428%')
      OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
    )
    AND p.anchor_age BETWEEN 73 AND 75
    AND a.dischtime IS NOT NULL
    -- Only keep admissions that map to a valid stay bucket and a known ED/elective grouping
    AND ( (TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) >= 1) )
)

, icu_chart_counts AS (
  SELECT
    ea.hadm_id,
    ea.stay_bucket,
    ea.ed_group,
    SUM(CASE
          WHEN LOWER(di_item.category) LIKE '%imaging%' OR LOWER(di_item.label) LIKE '%imaging%'
          THEN 1 ELSE 0 END) AS imaging_count,
    SUM(CASE
          WHEN LOWER(di_item.category) LIKE '%ecg%' OR LOWER(di_item.label) LIKE '%ecg%' OR LOWER(di_item.label) LIKE '%ekg%'
          THEN 1 ELSE 0 END) AS ecg_count,
    SUM(CASE
          WHEN LOWER(di_item.category) LIKE '%eeg%' OR LOWER(di_item.label) LIKE '%eeg%'
          THEN 1 ELSE 0 END) AS eeg_count,
    SUM(CASE
          WHEN LOWER(di_item.category) LIKE '%pulmonary function%' OR LOWER(di_item.label) LIKE '%pft%' OR LOWER(di_item.label) LIKE '%spirometry%' OR LOWER(di_item.category) LIKE '%pulmonary function test%'
          THEN 1 ELSE 0 END) AS pft_count
  FROM eligible_admissions ea
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON icu.hadm_id = ea.hadm_id AND icu.subject_id = ea.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di_item
    ON di_item.itemid = ce.itemid
  WHERE ce.charttime BETWEEN ea.admittime AND ea.dischtime
  GROUP BY ea.hadm_id, ea.stay_bucket, ea.ed_group
)

SELECT
  stay_bucket,
  ed_group,
  AVG(imaging_count) AS mean_imaging,
  AVG(ecg_count) AS mean_ecg,
  AVG(eeg_count) AS mean_eeg,
  AVG(pft_count) AS mean_pft
FROM icu_chart_counts
WHERE ed_group IS NOT NULL AND stay_bucket IS NOT NULL
GROUP BY stay_bucket, ed_group
ORDER BY stay_bucket, ed_group;