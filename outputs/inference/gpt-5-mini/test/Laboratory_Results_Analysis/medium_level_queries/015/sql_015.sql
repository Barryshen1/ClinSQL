WITH acs_adms AS (
  -- female admissions age 88-98 with an ACS diagnosis on the admission
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND (
      LOWER(d.long_title) LIKE '%myocardial infarction%' OR
      LOWER(d.long_title) LIKE '%acute coronary%' OR
      LOWER(d.long_title) LIKE '%unstable angina%'
    )
),
tnt_items AS (
  -- itemids plausibly representing Troponin T
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
     OR LOWER(label) LIKE '%trop t%'
),
first_tnt_per_adm AS (
  -- first Troponin T measurement (charttime >= admittime) per hadm_id
  SELECT
    le.hadm_id,
    le.subject_id,
    le.charttime,
    le.valuenum AS first_val,
    le.valueuom,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN tnt_items ti
    ON le.itemid = ti.itemid
  JOIN acs_adms a
    ON le.hadm_id = a.hadm_id
  WHERE le.charttime >= a.admittime
    AND le.valuenum IS NOT NULL
    -- restrict to units containing "ng" to reflect ng/mL; adjust if needed
    AND (LOWER(COALESCE(le.valueuom, '')) LIKE '%ng%')
)
SELECT
  quantiles[OFFSET(50)] AS median_ng_per_ml,
  quantiles[OFFSET(25)] AS p25_ng_per_ml,
  quantiles[OFFSET(75)] AS p75_ng_per_ml,
  (quantiles[OFFSET(75)] - quantiles[OFFSET(25)]) AS iqr_ng_per_ml,
  admissions_count
FROM (
  -- compute quantiles and count together to avoid mixing aggregation in outer query
  SELECT
    APPROX_QUANTILES(first_val, 100) AS quantiles,
    COUNT(*) AS admissions_count
  FROM (
    -- take only the first measurement per admission and require first_val > 0.01 ng/mL
    SELECT first_val
    FROM first_tnt_per_adm
    WHERE rn = 1
      AND first_val > 0.01
  )
);