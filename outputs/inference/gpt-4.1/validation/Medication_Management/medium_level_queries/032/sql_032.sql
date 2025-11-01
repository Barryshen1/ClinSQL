WITH
-- 1. Get diabetes and acute heart failure ICD codes
diabetes_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code LIKE '250%')
    OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E0[89]|^E1[0-3]'))
),
hf_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code IN ('42821','42823','42831','42833','42841','42843'))
    OR (icd_version = 10 AND icd_code IN (
      'I5021','I5023','I5031','I5033','I5041','I5043','I50811','I50813','I50821','I50823','I5084'
    ))
),
-- 2. Find admissions with both diabetes and acute heart failure
diabetes_adm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN diabetes_icd ON d.icd_code = diabetes_icd.icd_code AND d.icd_version = diabetes_icd.icd_version
),
hf_adm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN hf_icd ON d.icd_code = hf_icd.icd_code AND d.icd_version = hf_icd.icd_version
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.hadm_id IN (SELECT hadm_id FROM diabetes_adm)
    AND a.hadm_id IN (SELECT hadm_id FROM hf_adm)
    AND a.dischtime IS NOT NULL
),
-- 3. Identify insulin administrations in EMAR and prescriptions
insulin_emar AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.charttime,
    LOWER(ed.product_description) AS product_description,
    LOWER(e.event_txt) AS event_txt
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.subject_id = ed.subject_id AND e.emar_id = ed.emar_id AND e.emar_seq = ed.emar_seq
  WHERE
    (
      LOWER(ed.product_description) LIKE '%insulin%'
      OR LOWER(e.event_txt) LIKE '%insulin%'
    )
),
insulin_rx AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    LOWER(drug) AS drug,
    LOWER(formulary_drug_cd) AS formulary_drug_cd
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%insulin%'
),
-- 4. Classify regimen per admission and time window
regimen_windows AS (
  SELECT
    c.hadm_id,
    'first_24h' AS regimen_window,
    ARRAY_AGG(DISTINCT
      CASE
        WHEN
          (
            -- Basal: long-acting
            REGEXP_CONTAINS(product_description, r'glargine|detemir|degludec|nph')
            OR REGEXP_CONTAINS(drug, r'glargine|detemir|degludec|nph')
          )
        THEN 'Basal'
        WHEN
          (
            -- Bolus: rapid/short-acting
            REGEXP_CONTAINS(product_description, r'aspart|lispro|regular|glulisine')
            OR REGEXP_CONTAINS(drug, r'aspart|lispro|regular|glulisine')
          )
        THEN 'Bolus'
        WHEN
          (
            product_description LIKE '%sliding%'
            OR product_description LIKE '%ssi%'
            OR event_txt LIKE '%sliding%'
            OR event_txt LIKE '%ssi%'
          )
        THEN 'Sliding-scale'
        ELSE NULL
      END
    IGNORE NULLS) AS regimen_types
  FROM cohort c
  LEFT JOIN insulin_emar em ON c.hadm_id = em.hadm_id
    AND em.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  LEFT JOIN insulin_rx rx ON c.hadm_id = rx.hadm_id
    AND rx.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.hadm_id

  UNION ALL

  SELECT
    c.hadm_id,
    'final_12h' AS regimen_window,
    ARRAY_AGG(DISTINCT
      CASE
        WHEN
          (
            REGEXP_CONTAINS(product_description, r'glargine|detemir|degludec|nph')
            OR REGEXP_CONTAINS(drug, r'glargine|detemir|degludec|nph')
          )
        THEN 'Basal'
        WHEN
          (
            REGEXP_CONTAINS(product_description, r'aspart|lispro|regular|glulisine')
            OR REGEXP_CONTAINS(drug, r'aspart|lispro|regular|glulisine')
          )
        THEN 'Bolus'
        WHEN
          (
            product_description LIKE '%sliding%'
            OR product_description LIKE '%ssi%'
            OR event_txt LIKE '%sliding%'
            OR event_txt LIKE '%ssi%'
          )
        THEN 'Sliding-scale'
        ELSE NULL
      END
    IGNORE NULLS) AS regimen_types
  FROM cohort c
  LEFT JOIN insulin_emar em ON c.hadm_id = em.hadm_id
    AND em.charttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime
  LEFT JOIN insulin_rx rx ON c.hadm_id = rx.hadm_id
    AND rx.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime
  GROUP BY c.hadm_id
),
-- 5. For each window, classify regimen per hadm_id
regimen_class AS (
  SELECT
    hadm_id,
    regimen_window,
    CASE
      WHEN ARRAY_LENGTH(regimen_types) = 0 THEN 'None'
      WHEN 'Basal' IN UNNEST(regimen_types) AND 'Bolus' IN UNNEST(regimen_types) THEN 'Basal-Bolus'
      WHEN 'Basal' IN UNNEST(regimen_types) THEN 'Basal'
      WHEN 'Bolus' IN UNNEST(regimen_types) THEN 'Bolus'
      WHEN 'Sliding-scale' IN UNNEST(regimen_types) THEN 'Sliding-scale'
      ELSE 'Other'
    END AS regimen
  FROM regimen_windows
),
-- 6. Calculate prevalence per regimen and window
counts AS (
  SELECT
    regimen_window,
    regimen,
    COUNT(DISTINCT hadm_id) AS n
  FROM regimen_class
  WHERE regimen != 'None'
  GROUP BY regimen_window, regimen
),
total_cohort AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_n FROM cohort
),
-- 7. Pivot for output
pivot AS (
  SELECT
    regimen,
    MAX(CASE WHEN regimen_window = 'first_24h' THEN n ELSE 0 END) AS first_24h_n,
    MAX(CASE WHEN regimen_window = 'final_12h' THEN n ELSE 0 END) AS final_12h_n
  FROM counts
  GROUP BY regimen
),
-- 8. Final output with percentages
final AS (
  SELECT
    p.regimen,
    ROUND(100.0 * p.first_24h_n / t.total_n, 2) AS first_24h_percent,
    ROUND(100.0 * p.final_12h_n / t.total_n, 2) AS final_12h_percent,
    ROUND(100.0 * p.final_12h_n / t.total_n - 100.0 * p.first_24h_n / t.total_n, 2) AS percentage_point_change
  FROM pivot p
  CROSS JOIN total_cohort t
)
SELECT
  regimen,
  first_24h_percent,
  final_12h_percent,
  percentage_point_change
FROM final
WHERE regimen IN ('Basal-Bolus', 'Basal', 'Bolus', 'Sliding-scale')
ORDER BY regimen;