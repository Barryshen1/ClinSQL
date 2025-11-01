WITH patient_diagnoses AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (dd.icd_code LIKE 'E10%' OR dd.icd_code LIKE 'E11%' OR dd.icd_code LIKE 'O24.4%')
),
heart_failure_diagnoses AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    dd.icd_code LIKE 'I50%'
),
qualified_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 54 AND 64
),
patients_with_both AS (
  SELECT
    qp.subject_id,
    qp.hadm_id,
    qp.age_at_admit
  FROM
    qualified_patients qp
  INNER JOIN
    patient_diagnoses pd
    ON qp.subject_id = pd.subject_id AND qp.hadm_id = pd.hadm_id
  INNER JOIN
    heart_failure_diagnoses hf
    ON qp.subject_id = hf.subject_id AND qp.hadm_id = hf.hadm_id
),
first_icu_stay AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN
    patients_with_both p
    ON i.subject_id = p.subject_id AND i.hadm_id = p.hadm_id
),
first_icu_stay_filtered AS (
  SELECT *
  FROM first_icu_stay
  WHERE rn = 1
),
medications AS (
  SELECT
    f.stay_id,
    f.intime,
    f.outtime,
    p.drug,
    p.starttime,
    p.stoptime,
    -- Classify drug
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(p.drug) IN (
        'metformin', 'glipizide', 'glyburide', 'glimepiride',
        'sitagliptin', 'saxagliptin', 'linagliptin',
        'empagliflozin', 'dapagliflozin', 'canagliflozin',
        'pioglitazone', 'rosiglitazone',
        'glimepiride', 'repaglinide', 'nateglinide'
      ) THEN 'oral'
      ELSE 'other'
    END AS drug_class
  FROM
    first_icu_stay_filtered f
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON f.hadm_id = p.hadm_id
  WHERE
    p.starttime IS NOT NULL
),
windows AS (
  SELECT
    stay_id,
    -- Early window: first 12 hours
    intime AS early_start,
    DATETIME_ADD(intime, INTERVAL 12 HOUR) AS early_end,
    -- Late window: final 48 hours
    DATETIME_SUB(outtime, INTERVAL 48 HOUR) AS late_start,
    outtime AS late_end
  FROM
    first_icu_stay_filtered
),
meds_with_windows AS (
  SELECT
    m.stay_id,
    m.drug_class,
    w.early_start, w.early_end, w.late_start, w.late_end,
    m.starttime, m.stoptime,
    -- Check overlap with early window
    (m.starttime < w.early_end AND (m.stoptime IS NULL OR m.stoptime > w.early_start)) AS in_early_window,
    -- Check overlap with late window
    (m.starttime < w.late_end AND (m.stoptime IS NULL OR m.stoptime > w.late_start)) AS in_late_window
  FROM
    medications m
  INNER JOIN
    windows w
    ON m.stay_id = w.stay_id
),
stay_med_summary AS (
  SELECT
    stay_id,
    MAX(CASE WHEN drug_class = 'insulin' AND in_early_window THEN 1 ELSE 0 END) AS insulin_early,
    MAX(CASE WHEN drug_class = 'oral' AND in_early_window THEN 1 ELSE 0 END) AS oral_early,
    MAX(CASE WHEN drug_class = 'insulin' AND in_late_window THEN 1 ELSE 0 END) AS insulin_late,
    MAX(CASE WHEN drug_class = 'oral' AND in_late_window THEN 1 ELSE 0 END) AS oral_late
  FROM
    meds_with_windows
  GROUP BY
    stay_id
),
aggregated AS (
  SELECT
    COUNT(*) AS total_stays,
    AVG(insulin_early) AS insulin_early_prev,
    AVG(oral_early) AS oral_early_prev,
    AVG(insulin_late) AS insulin_late_prev,
    AVG(oral_late) AS oral_late_prev
  FROM
    stay_med_summary
)
SELECT
  ROUND(insulin_early_prev * 100, 2) AS insulin_prevalence_first_12h_pct,
  ROUND(oral_early_prev * 100, 2) AS oral_prevalence_first_12h_pct,
  ROUND(insulin_late_prev * 100, 2) AS insulin_prevalence_final_48h_pct,
  ROUND(oral_late_prev * 100, 2) AS oral_prevalence_final_48h_pct,
  ROUND(
    ((insulin_late_prev - oral_late_prev) - (insulin_early_prev - oral_early_prev)) * 100,
    2
  ) AS net_change_in_difference_pp
FROM
  aggregated;