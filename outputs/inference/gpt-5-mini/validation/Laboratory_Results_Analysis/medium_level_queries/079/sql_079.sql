WITH troponin_items AS (
  -- Identify lab itemids that correspond to Troponin T
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
     OR LOWER(label) LIKE '%troponin-t%'
     OR LOWER(label) LIKE '%trop t%'
),
eligible_admissions AS (
  -- Admissions for female patients age 82-92 with a diagnosis of chest pain or myocardial infarction
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.edregtime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND (
      LOWER(dd.long_title) LIKE '%chest pain%'
      OR LOWER(dd.long_title) LIKE '%myocardial infarction%'
      OR LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
    )
),
first_troponin_per_adm AS (
  -- Get the earliest Troponin T per admission within the ED/admission window
  SELECT
    hadm_id,
    subject_id,
    valuenum AS troponin_val,
    charttime
  FROM (
    SELECT
      l.subject_id,
      l.hadm_id,
      l.charttime,
      l.valuenum,
      ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime, l.storetime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN troponin_items ti
      ON l.itemid = ti.itemid
    JOIN eligible_admissions ea
      ON l.hadm_id = ea.hadm_id AND l.subject_id = ea.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON l.hadm_id = a.hadm_id
    WHERE l.valuenum IS NOT NULL
      -- Ensure lab is within the ED/admission window (include ED measurements if edregtime exists)
      AND l.charttime >= COALESCE(a.edregtime, a.admittime)
      AND l.charttime <= a.dischtime
  ) lab_first
  WHERE rn = 1
),
cohort_troponin_filtered AS (
  -- Keep only initial troponin > 0.01 ng/mL
  SELECT f.*
  FROM first_troponin_per_adm f
  WHERE f.troponin_val > 0.01
)

SELECT
  q.n_admissions,
  q.quantiles[OFFSET(0)] AS min_troponin,
  q.quantiles[OFFSET(1)] AS p25_troponin,
  q.quantiles[OFFSET(2)] AS median_troponin,
  q.quantiles[OFFSET(3)] AS p75_troponin,
  q.quantiles[OFFSET(4)] AS max_troponin
FROM (
  SELECT
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(troponin_val, 4) AS quantiles
  FROM cohort_troponin_filtered
) q;