WITH ami_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id
    AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE di.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%myocardial infarction%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
),

troponin_t_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
     OR LOWER(label) LIKE '%troponin-t%'
     OR LOWER(label) LIKE '%troponin, t%'
),

first_troponin_per_admission AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_t_items li
    ON le.itemid = li.itemid
  JOIN ami_admissions aa
    ON le.hadm_id = aa.hadm_id
    -- ensure the lab occurred during the hospital admission
    AND le.charttime BETWEEN aa.admittime AND aa.dischtime
  WHERE le.valuenum IS NOT NULL
)

SELECT
  agg.n_admissions_with_initial_tn_gt_0_04,
  agg.q[OFFSET(25)] AS q1_25th,
  agg.q[OFFSET(50)] AS median_50th,
  agg.q[OFFSET(75)] AS q3_75th,
  'units as recorded in labevents.valueuom (assumed ng/mL)' AS units_note
FROM (
  SELECT
    APPROX_QUANTILES(valuenum, 100) AS q,
    COUNT(*) AS n_admissions_with_initial_tn_gt_0_04
  FROM first_troponin_per_admission
  WHERE rn = 1
    AND valuenum > 0.04
) AS agg;