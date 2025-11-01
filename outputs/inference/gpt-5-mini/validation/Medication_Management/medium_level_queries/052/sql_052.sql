WITH
-- Cohort: admissions for male patients age 45-55 inclusive, LOS >= 48h, with T2DM and Heart Failure diagnoses
patients_45_55_male AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 45 AND 55
),

admissions_cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_45_55_male p ON p.subject_id = a.subject_id
  WHERE a.hadm_id IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
),

-- Identify admissions that have both Type 2 Diabetes and Heart Failure diagnoses
dx_flags AS (
  SELECT
    d.hadm_id,
    MAX(CASE
      WHEN (d.icd_version = 10 AND LOWER(di.long_title) LIKE '%diabetes mellitus%' AND d.icd_code LIKE 'E11%')
        OR (d.icd_version = 9 AND d.icd_code LIKE '250%')
        OR LOWER(di.long_title) LIKE '%type 2%' OR LOWER(di.long_title) LIKE '%non-insulin-dependent%'
      THEN 1 ELSE 0 END) AS has_t2dm,
    MAX(CASE
      WHEN (d.icd_version = 10 AND (d.icd_code LIKE 'I50%' OR LOWER(di.long_title) LIKE '%heart failure%'))
        OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
        OR LOWER(di.long_title) LIKE '%heart failure%'
      THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE d.hadm_id IS NOT NULL
  GROUP BY d.hadm_id
),

-- Final cohort: admissions meeting diagnosis criteria
cohort AS (
  SELECT ac.subject_id, ac.hadm_id, ac.admittime, ac.dischtime
  FROM admissions_cohort ac
  JOIN dx_flags df ON df.hadm_id = ac.hadm_id
  WHERE df.has_t2dm = 1 AND df.has_hf = 1
),

-- Helper to normalize windows per admission (renamed to avoid reserved keyword)
admission_windows AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    admittime AS first48_start,
    TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) AS first48_end,
    TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR) AS final24_start,
    dischtime AS final24_end
  FROM cohort
),

/* Medication detection from prescriptions (hospital) */
presc_meds AS (
  SELECT
    w.hadm_id,
    'insulin' AS med_category,
    'first48' AS window_name
  FROM admission_windows w
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = w.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime <= w.first48_end
    AND (pr.stoptime IS NULL OR pr.stoptime >= w.first48_start)
    AND (
      LOWER(pr.drug) LIKE '%insulin%' OR LOWER(pr.drug) LIKE '%glargine%' OR LOWER(pr.drug) LIKE '%detemir%'
      OR LOWER(pr.drug) LIKE '%degludec%' OR LOWER(pr.drug) LIKE '%lispro%' OR LOWER(pr.drug) LIKE '%aspart%'
      OR LOWER(pr.drug) LIKE '%humalog%' OR LOWER(pr.drug) LIKE '%novolog%' OR LOWER(pr.drug) LIKE '%regular insulin%'
    )
  UNION DISTINCT
  SELECT
    w.hadm_id,
    'oral' AS med_category,
    'first48' AS window_name
  FROM admission_windows w
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = w.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime <= w.first48_end
    AND (pr.stoptime IS NULL OR pr.stoptime >= w.first48_start)
    AND (
      LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%glipizide%'
      OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%gliclazide%' OR LOWER(pr.drug) LIKE '%sitagliptin%'
      OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%pioglitazone%'
      OR LOWER(pr.drug) LIKE '%rosiglitazone%' OR LOWER(pr.drug) LIKE '%repaglinide%' OR LOWER(pr.drug) LIKE '%nateglinide%'
      OR LOWER(pr.drug) LIKE '%acarbose%' OR LOWER(pr.drug) LIKE '%miglitol%' OR LOWER(pr.drug) LIKE '%canagliflozin%'
      OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%sulfonyl%'
      OR LOWER(pr.drug) LIKE '%gliptin%' OR LOWER(pr.drug) LIKE '%glitazone%'
    )
  UNION DISTINCT
  -- final24 from prescriptions
  SELECT
    w.hadm_id,
    'insulin' AS med_category,
    'final24' AS window_name
  FROM admission_windows w
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = w.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime <= w.final24_end
    AND (pr.stoptime IS NULL OR pr.stoptime >= w.final24_start)
    AND (
      LOWER(pr.drug) LIKE '%insulin%' OR LOWER(pr.drug) LIKE '%glargine%' OR LOWER(pr.drug) LIKE '%detemir%'
      OR LOWER(pr.drug) LIKE '%degludec%' OR LOWER(pr.drug) LIKE '%lispro%' OR LOWER(pr.drug) LIKE '%aspart%'
      OR LOWER(pr.drug) LIKE '%humalog%' OR LOWER(pr.drug) LIKE '%novolog%' OR LOWER(pr.drug) LIKE '%regular insulin%'
    )
  UNION DISTINCT
  SELECT
    w.hadm_id,
    'oral' AS med_category,
    'final24' AS window_name
  FROM admission_windows w
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = w.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime <= w.final24_end
    AND (pr.stoptime IS NULL OR pr.stoptime >= w.final24_start)
    AND (
      LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%glipizide%'
      OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%gliclazide%' OR LOWER(pr.drug) LIKE '%sitagliptin%'
      OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%pioglitazone%'
      OR LOWER(pr.drug) LIKE '%rosiglitazone%' OR LOWER(pr.drug) LIKE '%repaglinide%' OR LOWER(pr.drug) LIKE '%nateglinide%'
      OR LOWER(pr.drug) LIKE '%acarbose%' OR LOWER(pr.drug) LIKE '%miglitol%' OR LOWER(pr.drug) LIKE '%canagliflozin%'
      OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%sulfonyl%'
      OR LOWER(pr.drug) LIKE '%gliptin%' OR LOWER(pr.drug) LIKE '%glitazone%'
    )
),

/* Medication detection from pharmacy (hospital dispensing records) */
pharm_meds AS (
  SELECT
    w.hadm_id,
    'insulin' AS med_category,
    'first48' AS window_name
  FROM admission_windows w
  JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.hadm_id = w.hadm_id
  WHERE ph.starttime IS NOT NULL
    AND ph.starttime <= w.first48_end
    AND (ph.stoptime IS NULL OR ph.stoptime >= w.first48_start)
    AND (
      LOWER(ph.medication) LIKE '%insulin%' OR LOWER(ph.medication) LIKE '%glargine%' OR LOWER(ph.medication) LIKE '%detemir%'
      OR LOWER(ph.medication) LIKE '%degludec%' OR LOWER(ph.medication) LIKE '%lispro%' OR LOWER(ph.medication) LIKE '%aspart%'
      OR LOWER(ph.medication) LIKE '%humalog%' OR LOWER(ph.medication) LIKE '%novolog%' OR LOWER(ph.medication) LIKE '%regular insulin%'
    )
  UNION DISTINCT
  SELECT
    w.hadm_id,
    'oral' AS med_category,
    'first48' AS window_name
  FROM admission_windows w
  JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.hadm_id = w.hadm_id
  WHERE ph.starttime IS NOT NULL
    AND ph.starttime <= w.first48_end
    AND (ph.stoptime IS NULL OR ph.stoptime >= w.first48_start)
    AND (
      LOWER(ph.medication) LIKE '%metformin%' OR LOWER(ph.medication) LIKE '%glimepiride%' OR LOWER(ph.medication) LIKE '%glipizide%'
      OR LOWER(ph.medication) LIKE '%glyburide%' OR LOWER(ph.medication) LIKE '%gliclazide%' OR LOWER(ph.medication) LIKE '%sitagliptin%'
      OR LOWER(ph.medication) LIKE '%saxagliptin%' OR LOWER(ph.medication) LIKE '%linagliptin%' OR LOWER(ph.medication) LIKE '%pioglitazone%'
      OR LOWER(ph.medication) LIKE '%rosiglitazone%' OR LOWER(ph.medication) LIKE '%repaglinide%' OR LOWER(ph.medication) LIKE '%nateglinide%'
      OR LOWER(ph.medication) LIKE '%acarbose%' OR LOWER(ph.medication) LIKE '%miglitol%' OR LOWER(ph.medication) LIKE '%canagliflozin%'
      OR LOWER(ph.medication) LIKE '%dapagliflozin%' OR LOWER(ph.medication) LIKE '%empagliflozin%' OR LOWER(ph.medication) LIKE '%sulfonyl%'
      OR LOWER(ph.medication) LIKE '%gliptin%' OR LOWER(ph.medication) LIKE '%glitazone%'
    )
  UNION DISTINCT
  -- final24 from pharmacy
  SELECT
    w.hadm_id,
    'insulin' AS med_category,
    'final24' AS window_name
  FROM admission_windows w
  JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.hadm_id = w.hadm_id
  WHERE ph.starttime IS NOT NULL
    AND ph.starttime <= w.final24_end
    AND (ph.stoptime IS NULL OR ph.stoptime >= w.final24_start)
    AND (
      LOWER(ph.medication) LIKE '%insulin%' OR LOWER(ph.medication) LIKE '%glargine%' OR LOWER(ph.medication) LIKE '%detemir%'
      OR LOWER(ph.medication) LIKE '%degludec%' OR LOWER(ph.medication) LIKE '%lispro%' OR LOWER(ph.medication) LIKE '%aspart%'
      OR LOWER(ph.medication) LIKE '%humalog%' OR LOWER(ph.medication) LIKE '%novolog%' OR LOWER(ph.medication) LIKE '%regular insulin%'
    )
  UNION DISTINCT
  SELECT
    w.hadm_id,
    'oral' AS med_category,
    'final24' AS window_name
  FROM admission_windows w
  JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.hadm_id = w.hadm_id
  WHERE ph.starttime IS NOT NULL
    AND ph.starttime <= w.final24_end
    AND (ph.stoptime IS NULL OR ph.stoptime >= w.final24_start)
    AND (
      LOWER(ph.medication) LIKE '%metformin%' OR LOWER(ph.medication) LIKE '%glimepiride%' OR LOWER(ph.medication) LIKE '%glipizide%'
      OR LOWER(ph.medication) LIKE '%glyburide%' OR LOWER(ph.medication) LIKE '%gliclazide%' OR LOWER(ph.medication) LIKE '%sitagliptin%'
      OR LOWER(ph.medication) LIKE '%saxagliptin%' OR LOWER(ph.medication) LIKE '%linagliptin%' OR LOWER(ph.medication) LIKE '%pioglitazone%'
      OR LOWER(ph.medication) LIKE '%rosiglitazone%' OR LOWER(ph.medication) LIKE '%repaglinide%' OR LOWER(ph.medication) LIKE '%nateglinide%'
      OR LOWER(ph.medication) LIKE '%acarbose%' OR LOWER(ph.medication) LIKE '%miglitol%' OR LOWER(ph.medication) LIKE '%canagliflozin%'
      OR LOWER(ph.medication) LIKE '%dapagliflozin%' OR LOWER(ph.medication) LIKE '%empagliflozin%' OR LOWER(ph.medication) LIKE '%sulfonyl%'
      OR LOWER(ph.medication) LIKE '%gliptin%' OR LOWER(ph.medication) LIKE '%glitazone%'
    )
),

/* Medication detection from ICU inputevents (some insulin administrations recorded here) */
icu_meds AS (
  SELECT
    w.hadm_id,
    'insulin' AS med_category,
    'first48' AS window_name
  FROM admission_windows w
  JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON ie.hadm_id = w.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  WHERE ie.starttime BETWEEN w.first48_start AND w.first48_end
    AND (
      (di.label IS NOT NULL AND LOWER(di.label) LIKE '%insulin%')
      OR (LOWER(COALESCE(ie.ordercategoryname, '')) LIKE '%insulin%')
      OR (LOWER(COALESCE(ie.ordercomponenttypedescription, '')) LIKE '%insulin%')
    )
  UNION DISTINCT
  SELECT
    w.hadm_id,
    'oral' AS med_category,
    'first48' AS window_name
  FROM admission_windows w
  JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON ie.hadm_id = w.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  WHERE ie.starttime BETWEEN w.first48_start AND w.first48_end
    AND (
      (di.label IS NOT NULL AND (
         LOWER(di.label) LIKE '%metformin%' OR LOWER(di.label) LIKE '%glimepiride%' OR LOWER(di.label) LIKE '%glipizide%'
         OR LOWER(di.label) LIKE '%glyburide%' OR LOWER(di.label) LIKE '%sitagliptin%' OR LOWER(di.label) LIKE '%dapagliflozin%'
         OR LOWER(di.label) LIKE '%pioglitazone%' OR LOWER(di.label) LIKE '%saxagliptin%' OR LOWER(di.label) LIKE '%linagliptin%'
      ))
      OR (LOWER(COALESCE(ie.ordercategoryname, '')) LIKE '%metformin%')
    )
  UNION DISTINCT
  -- final24 from ICU inputevents
  SELECT
    w.hadm_id,
    'insulin' AS med_category,
    'final24' AS window_name
  FROM admission_windows w
  JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON ie.hadm_id = w.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  WHERE ie.starttime BETWEEN w.final24_start AND w.final24_end
    AND (
      (di.label IS NOT NULL AND LOWER(di.label) LIKE '%insulin%')
      OR (LOWER(COALESCE(ie.ordercategoryname, '')) LIKE '%insulin%')
      OR (LOWER(COALESCE(ie.ordercomponenttypedescription, '')) LIKE '%insulin%')
    )
  UNION DISTINCT
  SELECT
    w.hadm_id,
    'oral' AS med_category,
    'final24' AS window_name
  FROM admission_windows w
  JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON ie.hadm_id = w.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  WHERE ie.starttime BETWEEN w.final24_start AND w.final24_end
    AND (
      (di.label IS NOT NULL AND (
         LOWER(di.label) LIKE '%metformin%' OR LOWER(di.label) LIKE '%glimepiride%' OR LOWER(di.label) LIKE '%glipizide%'
         OR LOWER(di.label) LIKE '%glyburide%' OR LOWER(di.label) LIKE '%sitagliptin%' OR LOWER(di.label) LIKE '%dapagliflozin%'
         OR LOWER(di.label) LIKE '%pioglitazone%' OR LOWER(di.label) LIKE '%saxagliptin%' OR LOWER(di.label) LIKE '%linagliptin%'
      ))
      OR (LOWER(COALESCE(ie.ordercategoryname, '')) LIKE '%metformin%')
    )
),

-- Union all med signals and dedupe per hadm_id, med_category, window
all_med_signals AS (
  SELECT * FROM presc_meds
  UNION DISTINCT
  SELECT * FROM pharm_meds
  UNION DISTINCT
  SELECT * FROM icu_meds
),

-- For each hadm_id and window, does it have insulin and/or oral?
hadm_window_flags AS (
  SELECT
    w.hadm_id,
    w.subject_id,
    w.admittime,
    w.dischtime,
    'first48' AS window_name,
    MAX(CASE WHEN ams.med_category = 'insulin' THEN 1 ELSE 0 END) AS insulin,
    MAX(CASE WHEN ams.med_category = 'oral' THEN 1 ELSE 0 END) AS oral
  FROM admission_windows w
  LEFT JOIN all_med_signals ams
    ON ams.hadm_id = w.hadm_id AND ams.window_name = 'first48'
  GROUP BY w.hadm_id, w.subject_id, w.admittime, w.dischtime

  UNION ALL

  SELECT
    w.hadm_id,
    w.subject_id,
    w.admittime,
    w.dischtime,
    'final24' AS window_name,
    MAX(CASE WHEN ams.med_category = 'insulin' THEN 1 ELSE 0 END) AS insulin,
    MAX(CASE WHEN ams.med_category = 'oral' THEN 1 ELSE 0 END) AS oral
  FROM admission_windows w
  LEFT JOIN all_med_signals ams
    ON ams.hadm_id = w.hadm_id AND ams.window_name = 'final24'
  GROUP BY w.hadm_id, w.subject_id, w.admittime, w.dischtime
),

-- Cohort size (number of admissions)
cohort_size AS (
  SELECT COUNT(DISTINCT hadm_id) AS n_admissions
  FROM cohort
)

-- Final aggregation: percentages per window and med category
SELECT
  hw.window_name AS window,
  'Insulin' AS medication_type,
  ROUND(100.0 * SUM(hw.insulin) / cs.n_admissions, 2) AS percent_of_admissions
FROM hadm_window_flags hw, cohort_size cs
GROUP BY hw.window_name, cs.n_admissions
UNION ALL
SELECT
  hw.window_name AS window,
  'Oral agents' AS medication_type,
  ROUND(100.0 * SUM(hw.oral) / cs.n_admissions, 2) AS percent_of_admissions
FROM hadm_window_flags hw, cohort_size cs
GROUP BY hw.window_name, cs.n_admissions
ORDER BY window, medication_type;