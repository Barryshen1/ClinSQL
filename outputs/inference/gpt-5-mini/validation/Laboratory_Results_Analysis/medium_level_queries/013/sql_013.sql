WITH patients50_60_male AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 50 AND 60
),

adm_with_diag AS (
  -- admissions for patients in age/gender group that have ANY diagnosis matching chest pain / AMI phrases
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients50_60_male p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
    LOWER(dd.long_title) LIKE '%chest pain%'
    OR LOWER(dd.long_title) LIKE '%myocardial infarction%'
    OR LOWER(dd.long_title) LIKE '%acute myocardial%'
    OR LOWER(dd.long_title) LIKE '%angina%'
    OR LOWER(dd.long_title) LIKE '%acute coronary%'
    OR LOWER(dd.long_title) LIKE '%st elevation%'
  )
),

troponin_items AS (
  -- find lab itemids that look like troponin
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin%'
),

initial_troponin_per_adm AS (
  -- earliest troponin (by charttime) within each admission (hadm_id)
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS val,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC, le.labevent_id ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items ti ON le.itemid = ti.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id AND le.subject_id = a.subject_id
       AND le.charttime BETWEEN a.admittime AND a.dischtime
  WHERE le.valuenum IS NOT NULL
),

initial_tn_cohort AS (
  -- keep only initial troponin (rn = 1), only admissions that are in our diagnosis cohort,
  -- and apply ULN filter val > 0.014
  SELECT it.subject_id, it.hadm_id, it.val
  FROM initial_troponin_per_adm it
  JOIN adm_with_diag ad ON it.hadm_id = ad.hadm_id
  WHERE it.rn = 1
    AND it.val > 0.014
),

ordered_vals AS (
  -- create an ordered list and compute row numbers and total count
  SELECT
    val,
    ROW_NUMBER() OVER (ORDER BY val) AS row_num,
    COUNT(*) OVER () AS n
  FROM initial_tn_cohort
),

positions AS (
  -- compute desired positions for quantiles using (n+1)*p convention
  SELECT
    n,
    CAST(FLOOR((n + 1) / 2.0) AS INT64) AS m_pos1,
    CAST(CEIL((n + 1) / 2.0) AS INT64)  AS m_pos2,
    CAST(FLOOR((n + 1) / 4.0) AS INT64) AS q1_pos1,
    CAST(CEIL((n + 1) / 4.0) AS INT64)  AS q1_pos2,
    CAST(FLOOR(3 * (n + 1) / 4.0) AS INT64) AS q3_pos1,
    CAST(CEIL(3 * (n + 1) / 4.0) AS INT64)  AS q3_pos2
  FROM (SELECT n FROM ordered_vals LIMIT 1)
)

SELECT
  -- counts
  (SELECT COUNT(DISTINCT hadm_id) FROM initial_tn_cohort) AS admission_count,
  (SELECT COUNT(DISTINCT subject_id) FROM initial_tn_cohort) AS patient_count,

  -- mean
  (SELECT AVG(val) FROM initial_tn_cohort) AS mean_initial_hsTnT_ng_per_mL,

  -- median (average of m_pos1 and m_pos2 values as needed)
  (SELECT AVG(val)
   FROM ordered_vals ov
   CROSS JOIN positions pos
   WHERE ov.row_num IN (pos.m_pos1, pos.m_pos2)
  ) AS median_initial_hsTnT_ng_per_mL,

  -- Q1
  (SELECT AVG(val)
   FROM ordered_vals ov
   CROSS JOIN positions pos
   WHERE ov.row_num IN (pos.q1_pos1, pos.q1_pos2)
  ) AS Q1_initial_hsTnT_ng_per_mL,

  -- Q3
  (SELECT AVG(val)
   FROM ordered_vals ov
   CROSS JOIN positions pos
   WHERE ov.row_num IN (pos.q3_pos1, pos.q3_pos2)
  ) AS Q3_initial_hsTnT_ng_per_mL,

  -- IQR = Q3 - Q1
  ((SELECT AVG(val)
    FROM ordered_vals ov
    CROSS JOIN positions pos
    WHERE ov.row_num IN (pos.q3_pos1, pos.q3_pos2)
   )
   -
   (SELECT AVG(val)
    FROM ordered_vals ov
    CROSS JOIN positions pos
    WHERE ov.row_num IN (pos.q1_pos1, pos.q1_pos2)
   )
  ) AS IQR_initial_hsTnT_ng_per_mL
;