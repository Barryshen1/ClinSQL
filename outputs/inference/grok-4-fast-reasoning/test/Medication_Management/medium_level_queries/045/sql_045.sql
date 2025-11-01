WITH cohort AS (
  SELECT 
    a.hadm_id, 
    a.subject_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 54 AND 64
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '250.%')
          OR (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) BETWEEN 'E10' AND 'E14')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` hf
      WHERE hf.hadm_id = a.hadm_id
        AND (
          (hf.icd_version = 9 AND hf.icd_code LIKE '428.%')
          OR (hf.icd_version = 10 AND hf.icd_code LIKE 'I50%')
        )
    )
),
total_n AS (
  SELECT COUNT(*) AS n 
  FROM cohort
),
first_insulin AS (
  SELECT COUNT(DISTINCT c.hadm_id) AS num
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` e 
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed 
    ON e.emar_id = ed.emar_id AND e.emar_seq = ed.emar_seq
  WHERE e.charttime >= c.admittime
    AND e.charttime < c.admittime + INTERVAL 12 HOUR
    AND (LOWER(e.medication) LIKE '%insulin%' OR LOWER(ed.product_description) LIKE '%insulin%')
),
first_oral AS (
  SELECT COUNT(DISTINCT c.hadm_id) AS num
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` e 
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed 
    ON e.emar_id = ed.emar_id AND e.emar_seq = ed.emar_seq
  WHERE e.charttime >= c.admittime
    AND e.charttime < c.admittime + INTERVAL 12 HOUR
    AND ed.route = 'PO'
    AND (
      LOWER(e.medication) LIKE '%metformin%' OR
      LOWER(e.medication) LIKE '%glipizide%' OR
      LOWER(e.medication) LIKE '%glyburide%' OR
      LOWER(e.medication) LIKE '%glibenclamide%' OR
      LOWER(e.medication) LIKE '%glimepiride%' OR
      LOWER(e.medication) LIKE '%pioglitazone%' OR
      LOWER(e.medication) LIKE '%rosiglitazone%' OR
      LOWER(e.medication) LIKE '%sitagliptin%' OR
      LOWER(e.medication) LIKE '%linagliptin%' OR
      LOWER(e.medication) LIKE '%saxagliptin%' OR
      LOWER(e.medication) LIKE '%alogliptin%' OR
      LOWER(e.medication) LIKE '%dapagliflozin%' OR
      LOWER(e.medication) LIKE '%canagliflozin%' OR
      LOWER(e.medication) LIKE '%empagliflozin%' OR
      LOWER(e.medication) LIKE '%ertugliflozin%' OR
      LOWER(e.medication) LIKE '%acarbose%' OR
      LOWER(e.medication) LIKE '%miglitol%' OR
      LOWER(e.medication) LIKE '%repaglinide%' OR
      LOWER(e.medication) LIKE '%nateglinide%'
    )
),
last_insulin AS (
  SELECT COUNT(DISTINCT c.hadm_id) AS num
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` e 
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed 
    ON e.emar_id = ed.emar_id AND e.emar_seq = ed.emar_seq
  CROSS JOIN UNNEST([GREATEST(c.admittime, c.dischtime - INTERVAL 48 HOUR)]) AS last_start
  WHERE e.charttime >= last_start
    AND e.charttime <= c.dischtime
    AND (LOWER(e.medication) LIKE '%insulin%' OR LOWER(ed.product_description) LIKE '%insulin%')
),
last_oral AS (
  SELECT COUNT(DISTINCT c.hadm_id) AS num
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` e 
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed 
    ON e.emar_id = ed.emar_id AND e.emar_seq = ed.emar_seq
  CROSS JOIN UNNEST([GREATEST(c.admittime, c.dischtime - INTERVAL 48 HOUR)]) AS last_start
  WHERE e.charttime >= last_start
    AND e.charttime <= c.dischtime
    AND ed.route = 'PO'
    AND (
      LOWER(e.medication) LIKE '%metformin%' OR
      LOWER(e.medication) LIKE '%glipizide%' OR
      LOWER(e.medication) LIKE '%glyburide%' OR
      LOWER(e.medication) LIKE '%glibenclamide%' OR
      LOWER(e.medication) LIKE '%glimepiride%' OR
      LOWER(e.medication) LIKE '%pioglitazone%' OR
      LOWER(e.medication) LIKE '%rosiglitazone%' OR
      LOWER(e.medication) LIKE '%sitagliptin%' OR
      LOWER(e.medication) LIKE '%linagliptin%' OR
      LOWER(e.medication) LIKE '%saxagliptin%' OR
      LOWER(e.medication) LIKE '%alogliptin%' OR
      LOWER(e.medication) LIKE '%dapagliflozin%' OR
      LOWER(e.medication) LIKE '%canagliflozin%' OR
      LOWER(e.medication) LIKE '%empagliflozin%' OR
      LOWER(e.medication) LIKE '%ertugliflozin%' OR
      LOWER(e.medication) LIKE '%acarbose%' OR
      LOWER(e.medication) LIKE '%miglitol%' OR
      LOWER(e.medication) LIKE '%repaglinide%' OR
      LOWER(e.medication) LIKE '%nateglinide%'
    )
)
SELECT 
  tn.n AS total_patients,
  (fi.num * 100.0 / tn.n) AS insulin_first_12h_pp,
  (fo.num * 100.0 / tn.n) AS oral_first_12h_pp,
  (li.num * 100.0 / tn.n) AS insulin_final_48h_pp,
  (lo.num * 100.0 / tn.n) AS oral_final_48h_pp,
  ((li.num * 100.0 / tn.n) - (fi.num * 100.0 / tn.n)) AS net_change_insulin_pp,
  ((lo.num * 100.0 / tn.n) - (fo.num * 100.0 / tn.n)) AS net_change_oral_pp
FROM total_n tn
CROSS JOIN first_insulin fi
CROSS JOIN first_oral fo
CROSS JOIN last_insulin li
CROSS JOIN last_oral lo;