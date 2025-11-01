WITH acs_icd_codes AS (
  -- List of ACS ICD codes (ICD-9 and ICD-10)
  SELECT '410' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '411', 9 UNION ALL
  SELECT '413', 9 UNION ALL
  SELECT 'I20', 10 UNION ALL
  SELECT 'I21', 10 UNION ALL
  SELECT 'I22', 10 UNION ALL
  SELECT 'I23', 10
),
acs_admissions AS (
  -- Admissions for male patients aged 80-90 with ACS diagnosis
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    JOIN acs_icd_codes acs
      ON diag.icd_code = acs.icd_code AND diag.icd_version = acs.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 80 AND 90
),
hs_tnt_items AS (
  -- Find itemids for hs-TnT in d_labitems
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%troponin%'
    AND (
      LOWER(label) LIKE '%t%' -- Troponin T
      OR LOWER(label) LIKE '%hs%' -- high sensitivity
      OR LOWER(label) LIKE '%high%' -- high sensitivity
      OR LOWER(label) LIKE '%sensitive%'
    )
),
first_hs_tnt AS (
  -- For each ACS admission, get the first hs-TnT measurement
  SELECT
    la.subject_id,
    la.hadm_id,
    la.charttime,
    la.valuenum,
    la.valueuom,
    ROW_NUMBER() OVER (PARTITION BY la.hadm_id ORDER BY la.charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` la
    JOIN hs_tnt_items hs
      ON la.itemid = hs.itemid
    JOIN acs_admissions acs
      ON la.subject_id = acs.subject_id AND la.hadm_id = acs.hadm_id
  WHERE
    la.valuenum IS NOT NULL
)
,
first_hs_tnt_categorized AS (
  -- Only keep the first hs-TnT per admission and categorize
  SELECT
    f.subject_id,
    f.hadm_id,
    f.charttime,
    f.valuenum,
    f.valueuom,
    CASE
      -- If units are ng/mL
      WHEN LOWER(f.valueuom) = 'ng/ml' THEN
        CASE
          WHEN f.valuenum < 0.014 THEN 'Normal'
          WHEN f.valuenum >= 0.014 AND f.valuenum <= 0.052 THEN 'Borderline'
          WHEN f.valuenum > 0.052 THEN 'Myocardial Injury'
          ELSE 'Unknown'
        END
      -- If units are ng/L
      WHEN LOWER(f.valueuom) = 'ng/l' THEN
        CASE
          WHEN f.valuenum < 14 THEN 'Normal'
          WHEN f.valuenum >= 14 AND f.valuenum <= 52 THEN 'Borderline'
          WHEN f.valuenum > 52 THEN 'Myocardial Injury'
          ELSE 'Unknown'
        END
      ELSE 'Unknown'
    END AS hs_tnt_category
  FROM first_hs_tnt f
  WHERE f.rn = 1
)
,
final AS (
  -- Join with admissions to get LOS
  SELECT
    acs.subject_id,
    acs.hadm_id,
    acs.anchor_age,
    acs.gender,
    acs.admittime,
    acs.dischtime,
    hs.hs_tnt_category,
    hs.valuenum,
    hs.valueuom,
    hs.charttime,
    -- LOS in days
    SAFE_CAST(TIMESTAMP_DIFF(acs.dischtime, acs.admittime, SECOND) AS FLOAT64)/86400 AS los
  FROM acs_admissions acs
    JOIN first_hs_tnt_categorized hs
      ON acs.subject_id = hs.subject_id AND acs.hadm_id = hs.hadm_id
  WHERE hs.hs_tnt_category != 'Unknown'
)
SELECT
  hs_tnt_category,
  COUNT(*) AS admission_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage_of_acs_admissions,
  ROUND(AVG(los), 2) AS mean_hospital_los_days
FROM final
GROUP BY hs_tnt_category
ORDER BY
  CASE hs_tnt_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
    ELSE 4
  END
;