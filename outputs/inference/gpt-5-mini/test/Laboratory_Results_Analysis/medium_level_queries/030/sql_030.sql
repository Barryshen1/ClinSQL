WITH troponin_items AS (
  SELECT DISTINCT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    -- match common label variants for high-sensitivity Troponin T
    LOWER(label) LIKE '%troponin t%'
    OR LOWER(label) LIKE '%troponin, t%'
    OR LOWER(label) LIKE '%troponin-t%'
    OR LOWER(label) LIKE '%troponin hs%'
    OR LOWER(label) LIKE '%high-sensitivity troponin%'
),
ami_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- ICD-9 acute MI codes (410.*)
          (d.icd_version = 9 AND d.icd_code LIKE '410%')
          -- ICD-10 acute MI codes (I21.*, I22.*)
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
        )
    )
),
index_tn_raw AS (
  -- all troponin measurements during the admission with numeric values
  SELECT aa.hadm_id, aa.subject_id, le.itemid, le.charttime, le.valuenum
  FROM ami_admissions aa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = aa.hadm_id
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  WHERE le.charttime BETWEEN aa.admittime AND aa.dischtime
    AND le.valuenum IS NOT NULL
),
index_tn AS (
  -- pick the earliest troponin measurement per admission (deterministic tie-breaker by itemid)
  SELECT hadm_id, subject_id, itemid, charttime, valuenum
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC, itemid ASC) AS rn
    FROM index_tn_raw
  )
  WHERE rn = 1
)
SELECT
  category,
  COUNT(*) AS n,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_admissions_with_tn
FROM (
  SELECT
    CASE
      WHEN valuenum <= 0.014 THEN 'Normal (<=0.014)'
      WHEN valuenum >= 0.015 AND valuenum <= 0.052 THEN 'Borderline (0.015-0.052)'
      WHEN valuenum > 0.052 THEN 'Myocardial Injury (>0.052)'
      ELSE 'Uncategorized'
    END AS category
  FROM index_tn
)
GROUP BY category
ORDER BY
  CASE
    WHEN category LIKE 'Normal%' THEN 1
    WHEN category LIKE 'Borderline%' THEN 2
    WHEN category LIKE 'Myocardial Injury%' THEN 3
    ELSE 4
  END;