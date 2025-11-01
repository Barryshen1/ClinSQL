WITH dx_adms AS (
  -- Admissions for male patients age 35-45 with a diagnosis mentioning chest pain or myocardial infarction
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.edregtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND (
      LOWER(dd.long_title) LIKE '%chest pain%'
      OR LOWER(dd.long_title) LIKE '%acute myocardial%'
      OR LOWER(dd.long_title) LIKE '%myocardial infarction%'
    )
),

troponin_items AS (
  -- Identify high-sensitivity Troponin T itemids by label (label must indicate Troponin T and high-sensitivity)
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND (LOWER(label) LIKE '%hs%' OR LOWER(label) LIKE '%high%')
),

first_hs_tn AS (
  -- For each admission, pick the earliest hs-TnT measurement (within ED/admission window)
  SELECT
    le.hadm_id,
    le.subject_id,
    COALESCE(le.charttime, le.storetime) AS charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY COALESCE(le.charttime, le.storetime) ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN dx_adms a
    ON le.hadm_id = a.hadm_id
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
    -- include lab draws from ED registration (if present) or admission time through discharge
    AND COALESCE(le.charttime, le.storetime) BETWEEN COALESCE(a.edregtime, a.admittime) AND a.dischtime
)

SELECT
  CASE
    WHEN valuenum < 14 THEN 'normal (<14 ng/L)'
    WHEN valuenum < 52 THEN 'borderline (14–52 ng/L)'
    ELSE 'myocardial injury (>=52 ng/L)'
  END AS category,
  COUNT(*) AS admissions_count
FROM first_hs_tn
WHERE rn = 1
GROUP BY category
ORDER BY
  CASE
    WHEN category LIKE 'normal%' THEN 1
    WHEN category LIKE 'borderline%' THEN 2
    ELSE 3
  END;