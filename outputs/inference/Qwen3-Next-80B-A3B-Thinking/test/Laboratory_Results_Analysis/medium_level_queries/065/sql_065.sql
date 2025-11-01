WITH first_troponin AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE di.label = 'Troponin T'
),
filtered_admissions AS (
  SELECT
    ft.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN first_troponin ft
    ON a.hadm_id = ft.hadm_id
  WHERE
    d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND ft.rn = 1
    AND ft.valuenum > 0.04
)
SELECT
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) AS median,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS iqr
FROM filtered_admissions;