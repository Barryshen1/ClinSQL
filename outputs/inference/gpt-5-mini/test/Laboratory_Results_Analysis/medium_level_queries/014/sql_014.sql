WITH patients_cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 79 AND 89
),

-- Admissions that have an ACS diagnosis (broad ICD/text matching)
acs_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON d.icd_code = ddi.icd_code
    AND d.icd_version = ddi.icd_version
  WHERE (
      UPPER(COALESCE(d.icd_code, '')) LIKE 'I2%'   -- I21*, I22* (ICD-10 AMI)
      OR UPPER(COALESCE(d.icd_code, '')) LIKE 'I20%' -- unstable angina I20.0 etc
      OR UPPER(COALESCE(d.icd_code, '')) LIKE '410%' -- ICD-9 AMI
      OR UPPER(COALESCE(d.icd_code, '')) LIKE '411%' -- some acute ischemic heart disease codes
      OR (ddi.long_title IS NOT NULL AND (
            LOWER(ddi.long_title) LIKE '%acute%' AND
            (LOWER(ddi.long_title) LIKE '%myocardial%' OR LOWER(ddi.long_title) LIKE '%infarction%' OR LOWER(ddi.long_title) LIKE '%angina%' OR LOWER(ddi.long_title) LIKE '%coronary%')
         ))
    )
),

-- Troponin T lab itemids
troponin_t_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
     OR LOWER(label) LIKE '%trop t%'
     OR LOWER(label) LIKE '%troponin-t%'
),

-- Earliest troponin T per admission (only troponin tests during the hospital admission)
first_troponin AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    le.labevent_id,
    le.charttime,
    le.storetime,
    COALESCE(
      le.valuenum,
      SAFE_CAST(REGEXP_EXTRACT(le.value, r'([0-9]+(?:\.[0-9]+)?)') AS FLOAT64)
    ) AS troponin_value,
    le.value AS value_text,
    le.valueuom,
    le.ref_range_lower,
    le.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY COALESCE(le.charttime, le.storetime) ASC) AS rn
  FROM acs_admissions a
  JOIN patients_cohort p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
  JOIN troponin_t_items ti
    ON le.itemid = ti.itemid
  WHERE COALESCE(le.charttime, le.storetime) >= a.admittime
    AND COALESCE(le.charttime, le.storetime) <= a.dischtime
)

SELECT
  t.category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent_of_measured
FROM (
  SELECT
    hadm_id,
    subject_id,
    troponin_value,
    CASE
      WHEN troponin_value IS NULL THEN 'MissingNumeric'
      WHEN troponin_value < 0.014 THEN 'Normal (<0.014)'
      WHEN troponin_value BETWEEN 0.014 AND 0.04 THEN 'Borderline (0.014 - 0.04)'
      WHEN troponin_value > 0.04 THEN 'Elevated (>0.04)'
      ELSE 'Uncategorized'
    END AS category
  FROM first_troponin
  WHERE rn = 1
) AS t
-- Exclude rows where there was no numeric troponin value, if you want only measured values:
WHERE t.category != 'MissingNumeric'
GROUP BY t.category
ORDER BY
  CASE
    WHEN t.category LIKE 'Normal%' THEN 1
    WHEN t.category LIKE 'Borderline%' THEN 2
    WHEN t.category LIKE 'Elevated%' THEN 3
    ELSE 4
  END;