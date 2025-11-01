WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.discharge_location,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE
    pt.gender = 'M'
    AND pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) BETWEEN 53 AND 63
    AND adm.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (icd_version = 9 AND icd_code LIKE '428%') OR
        (icd_version = 10 AND icd_code LIKE 'I50%')
    )
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) >= 1  -- Exclude LOS <1 day
),
charlson_map AS (
  SELECT
    hadm_id,
    SUM(weight) AS charlson_score
  FROM (
    SELECT
      hadm_id,
      CASE
        -- Myocardial Infarct
        WHEN (icd_version = 9 AND icd_code LIKE '410%' AND icd_code NOT LIKE '410%2') 
             OR (icd_version = 10 AND icd_code LIKE 'I21%' AND icd_code NOT LIKE 'I22%') THEN 1
        -- Congestive Heart Failure (excluded as cohort-defining condition)
        -- Cerebrovascular Disease
        WHEN (icd_version = 9 AND icd_code LIKE '43%') 
             OR (icd_version = 10 AND (icd_code LIKE 'G45%' OR icd_code LIKE 'I6%')) THEN 1
        -- Dementia
        WHEN (icd_version = 9 AND icd_code LIKE '290%') 
             OR (icd_version = 10 AND icd_code LIKE 'F0%') THEN 1
        -- Chronic Pulmonary Disease
        WHEN (icd_version = 9 AND (icd_code LIKE '490%' OR icd_code LIKE '491%' OR icd_code LIKE '492%' OR icd_code LIKE '493%' OR icd_code LIKE '494%' OR icd_code LIKE '495%' OR icd_code LIKE '496%' OR icd_code LIKE '500%' OR icd_code LIKE '501%' OR icd_code LIKE '502%' OR icd_code LIKE '503%' OR icd_code LIKE '504%' OR icd_code LIKE '505%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'J4%' OR icd_code LIKE 'J6%' OR icd_code LIKE 'J7%' OR icd_code = 'I278' OR icd_code = 'I279' OR icd_code LIKE 'J684%' OR icd_code LIKE 'J701%' OR icd_code LIKE 'J703%')) THEN 1
        -- Rheumatologic Disease
        WHEN (icd_version = 9 AND (icd_code LIKE '710%' OR icd_code LIKE '714%' OR icd_code LIKE '725%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'M05%' OR icd_code LIKE 'M06%' OR icd_code LIKE 'M315%' OR icd_code LIKE 'M32%' OR icd_code LIKE 'M33%' OR icd_code LIKE 'M34%' OR icd_code LIKE 'M351%' OR icd_code LIKE 'M353%' OR icd_code LIKE 'M360%')) THEN 1
        -- Peptic Ulcer Disease
        WHEN (icd_version = 9 AND (icd_code LIKE '531%' OR icd_code LIKE '532%' OR icd_code LIKE '533%' OR icd_code LIKE '534%') 
             OR (icd_version = 10 AND (icd_code LIKE 'K25%' OR icd_code LIKE 'K26%' OR icd_code LIKE 'K27%' OR icd_code LIKE 'K28%')) THEN 1
        -- Mild Liver Disease
        WHEN (icd_version = 9 AND (icd_code LIKE '570%' OR icd_code LIKE '571%' OR icd_code = '5733' OR icd_code = '5734' OR icd_code = '5738' OR icd_code = '5739' OR icd_code LIKE 'V427%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'B18%' OR icd_code LIKE 'K73%' OR icd_code LIKE 'K74%' OR icd_code = 'K700' OR icd_code = 'K701' OR icd_code = 'K702' OR icd_code = 'K703' OR icd_code = 'K709' OR icd_code = 'K713' OR icd_code = 'K714' OR icd_code = 'K715' OR icd_code = 'K717' OR icd_code LIKE 'K760%' OR icd_code = 'K762' OR icd_code = 'K763' OR icd_code = 'K764' OR icd_code = 'K768' OR icd_code = 'K769' OR icd_code = 'Z944')) THEN 1
        -- Diabetes (uncomplicated)
        WHEN (icd_version = 9 AND (icd_code LIKE '2500%' OR icd_code LIKE '2501%' OR icd_code LIKE '2502%' OR icd_code LIKE '2503%' OR icd_code LIKE '2508%' OR icd_code LIKE '2509%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%') AND icd_code NOT LIKE '%0' AND icd_code NOT LIKE '%1' AND icd_code NOT LIKE '%3') THEN 1
        -- Diabetes (complicated)
        WHEN (icd_version = 9 AND (icd_code LIKE '2504%' OR icd_code LIKE '2505%' OR icd_code LIKE '2506%' OR icd_code LIKE '2507%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%') AND (icd_code LIKE '%2' OR icd_code LIKE '%4' OR icd_code LIKE '%5' OR icd_code LIKE '%6' OR icd_code LIKE '%7' OR icd_code LIKE '%8')) THEN 2
        -- Hemiplegia or Paraplegia
        WHEN (icd_version = 9 AND (icd_code LIKE '3441%' OR icd_code LIKE '342%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'G81%' OR icd_code LIKE 'G82%' OR icd_code LIKE 'G041%' OR icd_code LIKE 'G114%' OR icd_code LIKE 'G801%' OR icd_code LIKE 'G802%' OR icd_code LIKE 'G830%' OR icd_code LIKE 'G831%' OR icd_code LIKE 'G832%' OR icd_code LIKE 'G833%' OR icd_code LIKE 'G834%' OR icd_code = 'G839')) THEN 2
        -- Renal Disease
        WHEN (icd_version = 9 AND (icd_code LIKE '403%' OR icd_code LIKE '404%' OR icd_code LIKE '582%' OR icd_code LIKE '583%' OR icd_code LIKE '585%' OR icd_code LIKE '586%' OR icd_code LIKE '588%' OR icd_code = 'V420' OR icd_code = 'V451' OR icd_code LIKE 'V56%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'I12%' OR icd_code LIKE 'I13%' OR icd_code LIKE 'N03%' OR icd_code LIKE 'N05%' OR icd_code LIKE 'N18%' OR icd_code LIKE 'N19%' OR icd_code LIKE 'N25%' OR icd_code = 'Z490' OR icd_code = 'Z491' OR icd_code = 'Z492' OR icd_code = 'Z940' OR icd_code = 'Z992')) THEN 2
        -- Any Malignancy
        WHEN (icd_version = 9 AND (icd_code LIKE '14%' OR icd_code LIKE '15%' OR icd_code LIKE '16%' OR icd_code LIKE '17%' OR icd_code LIKE '18%' OR icd_code LIKE '19%' OR icd_code LIKE '20%' OR icd_code LIKE '2386%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'C%' OR icd_code LIKE 'D0%' OR icd_code LIKE 'D37%' OR icd_code LIKE 'D38%' OR icd_code LIKE 'D39%' OR icd_code LIKE 'D4%') AND icd_code NOT LIKE 'D3%' AND icd_code NOT LIKE 'D41%') THEN 2
        -- Moderate/Severe Liver Disease
        WHEN (icd_version = 9 AND (icd_code LIKE '4560%' OR icd_code LIKE '4561%' OR icd_code LIKE '4562%' OR icd_code = '5722' OR icd_code = '5723' OR icd_code = '5724' OR icd_code = '5728' OR icd_code = '5735')) 
             OR (icd_version = 10 AND (icd_code LIKE 'I85%' OR icd_code LIKE 'I864%' OR icd_code LIKE 'I982%' OR icd_code LIKE 'K704%' OR icd_code LIKE 'K711%' OR icd_code LIKE 'K721%' OR icd_code LIKE 'K729%' OR icd_code LIKE 'K765%' OR icd_code LIKE 'K766%' OR icd_code LIKE 'K767%')) THEN 3
        -- Metastatic Solid Tumor
        WHEN (icd_version = 9 AND (icd_code LIKE '196%' OR icd_code LIKE '197%' OR icd_code LIKE '198%' OR icd_code LIKE '199%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'C77%' OR icd_code LIKE 'C78%' OR icd_code LIKE 'C79%' OR icd_code LIKE 'C80%')) THEN 6
        -- AIDS/HIV
        WHEN (icd_version = 9 AND (icd_code LIKE '042%' OR icd_code LIKE '043%' OR icd_code LIKE '044%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'B20%' OR icd_code LIKE 'B21%' OR icd_code LIKE 'B22%' OR icd_code LIKE 'B24%')) THEN 6
        ELSE 0
      END AS weight
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  )
  GROUP BY hadm_id
),
cohort_with_charlson AS (
  SELECT
    c.*,
    COALESCE(cm.charlson_score, 0) AS charlson_score,
    CASE
      WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN c.los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN c.los_days >= 8 THEN '>=8'
    END AS los_group,
    CASE
      WHEN COALESCE(cm.charlson_score, 0) <= 3 THEN '<=3'
      WHEN COALESCE(cm.charlson_score, 0) BETWEEN 4 AND 5 THEN '4-5'
      WHEN COALESCE(cm.charlson_score, 0) > 5 THEN '>5'
    END AS charlson_group
  FROM cohort c
  LEFT JOIN charlson_map cm
    ON c.hadm_id = cm.hadm_id
)
SELECT
  los_group,
  charlson_group,
  COUNT(*) AS total_admissions,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct
FROM cohort_with_charlson
GROUP BY los_group, charlson_group
ORDER BY los_group, charlson_group;

-- Part 2: Average LOS and differences by Charlson groups
WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.discharge_location,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE
    pt.gender = 'M'
    AND pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) BETWEEN 53 AND 63
    AND adm.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (icd_version = 9 AND icd_code LIKE '428%') OR
        (icd_version = 10 AND icd_code LIKE 'I50%')
    )
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) >= 1
),
charlson_map AS (
  SELECT
    hadm_id,
    SUM(weight) AS charlson_score
  FROM (
    SELECT
      hadm_id,
      CASE
        WHEN (icd_version = 9 AND icd_code LIKE '410%' AND icd_code NOT LIKE '410%2') 
             OR (icd_version = 10 AND icd_code LIKE 'I21%' AND icd_code NOT LIKE 'I22%') THEN 1
        WHEN (icd_version = 9 AND icd_code LIKE '43%') 
             OR (icd_version = 10 AND (icd_code LIKE 'G45%' OR icd_code LIKE 'I6%')) THEN 1
        WHEN (icd_version = 9 AND icd_code LIKE '290%') 
             OR (icd_version = 10 AND icd_code LIKE 'F0%') THEN 1
        WHEN (icd_version = 9 AND (icd_code LIKE '490%' OR icd_code LIKE '491%' OR icd_code LIKE '492%' OR icd_code LIKE '493%' OR icd_code LIKE '494%' OR icd_code LIKE '495%' OR icd_code LIKE '496%' OR icd_code LIKE '500%' OR icd_code LIKE '501%' OR icd_code LIKE '502%' OR icd_code LIKE '503%' OR icd_code LIKE '504%' OR icd_code LIKE '505%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'J4%' OR icd_code LIKE 'J6%' OR icd_code LIKE 'J7%' OR icd_code = 'I278' OR icd_code = 'I279' OR icd_code LIKE 'J684%' OR icd_code LIKE 'J701%' OR icd_code LIKE 'J703%')) THEN 1
        WHEN (icd_version = 9 AND (icd_code LIKE '710%' OR icd_code LIKE '714%' OR icd_code LIKE '725%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'M05%' OR icd_code LIKE 'M06%' OR icd_code LIKE 'M315%' OR icd_code LIKE 'M32%' OR icd_code LIKE 'M33%' OR icd_code LIKE 'M34%' OR icd_code LIKE 'M351%' OR icd_code LIKE 'M353%' OR icd_code LIKE 'M360%')) THEN 1
        WHEN (icd_version = 9 AND (icd_code LIKE '531%' OR icd_code LIKE '532%' OR icd_code LIKE '533%' OR icd_code LIKE '534%') 
             OR (icd_version = 10 AND (icd_code LIKE 'K25%' OR icd_code LIKE 'K26%' OR icd_code LIKE 'K27%' OR icd_code LIKE 'K28%')) THEN 1
        WHEN (icd_version = 9 AND (icd_code LIKE '570%' OR icd_code LIKE '571%' OR icd_code = '5733' OR icd_code = '5734' OR icd_code = '5738' OR icd_code = '5739' OR icd_code LIKE 'V427%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'B18%' OR icd_code LIKE 'K73%' OR icd_code LIKE 'K74%' OR icd_code = 'K700' OR icd_code = 'K701' OR icd_code = 'K702' OR icd_code = 'K703' OR icd_code = 'K709' OR icd_code = 'K713' OR icd_code = 'K714' OR icd_code = 'K715' OR icd_code = 'K717' OR icd_code LIKE 'K760%' OR icd_code = 'K762' OR icd_code = 'K763' OR icd_code = 'K764' OR icd_code = 'K768' OR icd_code = 'K769' OR icd_code = 'Z944')) THEN 1
        WHEN (icd_version = 9 AND (icd_code LIKE '2500%' OR icd_code LIKE '2501%' OR icd_code LIKE '2502%' OR icd_code LIKE '2503%' OR icd_code LIKE '2508%' OR icd_code LIKE '2509%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%') AND icd_code NOT LIKE '%0' AND icd_code NOT LIKE '%1' AND icd_code NOT LIKE '%3') THEN 1
        WHEN (icd_version = 9 AND (icd_code LIKE '2504%' OR icd_code LIKE '2505%' OR icd_code LIKE '2506%' OR icd_code LIKE '2507%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%') AND (icd_code LIKE '%2' OR icd_code LIKE '%4' OR icd_code LIKE '%5' OR icd_code LIKE '%6' OR icd_code LIKE '%7' OR icd_code LIKE '%8')) THEN 2
        WHEN (icd_version = 9 AND (icd_code LIKE '3441%' OR icd_code LIKE '342%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'G81%' OR icd_code LIKE 'G82%' OR icd_code LIKE 'G041%' OR icd_code LIKE 'G114%' OR icd_code LIKE 'G801%' OR icd_code LIKE 'G802%' OR icd_code LIKE 'G830%' OR icd_code LIKE 'G831%' OR icd_code LIKE 'G832%' OR icd_code LIKE 'G833%' OR icd_code LIKE 'G834%' OR icd_code = 'G839')) THEN 2
        WHEN (icd_version = 9 AND (icd_code LIKE '403%' OR icd_code LIKE '404%' OR icd_code LIKE '582%' OR icd_code LIKE '583%' OR icd_code LIKE '585%' OR icd_code LIKE '586%' OR icd_code LIKE '588%' OR icd_code = 'V420' OR icd_code = 'V451' OR icd_code LIKE 'V56%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'I12%' OR icd_code LIKE 'I13%' OR icd_code LIKE 'N03%' OR icd_code LIKE 'N05%' OR icd_code LIKE 'N18%' OR icd_code LIKE 'N19%' OR icd_code LIKE 'N25%' OR icd_code = 'Z490' OR icd_code = 'Z491' OR icd_code = 'Z492' OR icd_code = 'Z940' OR icd_code = 'Z992')) THEN 2
        WHEN (icd_version = 9 AND (icd_code LIKE '14%' OR icd_code LIKE '15%' OR icd_code LIKE '16%' OR icd_code LIKE '17%' OR icd_code LIKE '18%' OR icd_code LIKE '19%' OR icd_code LIKE '20%' OR icd_code LIKE '2386%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'C%' OR icd_code LIKE 'D0%' OR icd_code LIKE 'D37%' OR icd_code LIKE 'D38%' OR icd_code LIKE 'D39%' OR icd_code LIKE 'D4%') AND icd_code NOT LIKE 'D3%' AND icd_code NOT LIKE 'D41%') THEN 2
        WHEN (icd_version = 9 AND (icd_code LIKE '4560%' OR icd_code LIKE '4561%' OR icd_code LIKE '4562%' OR icd_code = '5722' OR icd_code = '5723' OR icd_code = '5724' OR icd_code = '5728' OR icd_code = '5735')) 
             OR (icd_version = 10 AND (icd_code LIKE 'I85%' OR icd_code LIKE 'I864%' OR icd_code LIKE 'I982%' OR icd_code LIKE 'K704%' OR icd_code LIKE 'K711%' OR icd_code LIKE 'K721%' OR icd_code LIKE 'K729%' OR icd_code LIKE 'K765%' OR icd_code LIKE 'K766%' OR icd_code LIKE 'K767%')) THEN 3
        WHEN (icd_version = 9 AND (icd_code LIKE '196%' OR icd_code LIKE '197%' OR icd_code LIKE '198%' OR icd_code LIKE '199%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'C77%' OR icd_code LIKE 'C78%' OR icd_code LIKE 'C79%' OR icd_code LIKE 'C80%')) THEN 6
        WHEN (icd_version = 9 AND (icd_code LIKE '042%' OR icd_code LIKE '043%' OR icd_code LIKE '044%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'B20%' OR icd_code LIKE 'B21%' OR icd_code LIKE 'B22%' OR icd_code LIKE 'B24%')) THEN 6
        ELSE 0
      END AS weight
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  )
  GROUP BY hadm_id
),
cohort_with_charlson AS (
  SELECT
    c.*,
    COALESCE(cm.charlson_score, 0) AS charlson_score,
    CASE
      WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN c.los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN c.los_days >= 8 THEN '>=8'
    END AS los_group,
    CASE
      WHEN COALESCE(cm.charlson_score, 0) <= 3 THEN '<=3'
      WHEN COALESCE(cm.charlson_score, 0) BETWEEN 4 AND 5 THEN '4-5'
      WHEN COALESCE(cm.charlson_score, 0) > 5 THEN '>5'
    END AS charlson_group
  FROM cohort c
  LEFT JOIN charlson_map cm
    ON c.hadm_id = cm.hadm_id
),
charlson_avg AS (
  SELECT
    charlson_group,
    ROUND(AVG(los_days), 2) AS avg_los
  FROM cohort_with_charlson
  GROUP BY charlson_group
)
SELECT
  a.charlson_group AS group_a,
  b.charlson_group AS group_b,
  ROUND(a.avg_los - b.avg_los, 2) AS abs_los_diff,
  ROUND(100.0 * (a.avg_los - b.avg_los) / b.avg_los, 2) AS rel_los_diff_pct
FROM charlson_avg a
CROSS JOIN charlson_avg b
WHERE a.charlson_group > b.charlson_group
ORDER BY a.charlson_group, b.charlson_group;

-- Part 3: Discharge destination distribution
WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.discharge_location,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE
    pt.gender = 'M'
    AND pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) BETWEEN 53 AND 63
    AND adm.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (icd_version = 9 AND icd_code LIKE '428%') OR
        (icd_version = 10 AND icd_code LIKE 'I50%')
    )
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) >= 1
),
charlson_map AS (
  SELECT
    hadm_id,
    SUM(weight) AS charlson_score
  FROM (
    SELECT
      hadm_id,
      CASE
        WHEN (icd_version = 9 AND icd_code LIKE '410%' AND icd_code NOT LIKE '410%2') 
             OR (icd_version = 10 AND icd_code LIKE 'I21%' AND icd_code NOT LIKE 'I22%') THEN 1
        WHEN (icd_version = 9 AND icd_code LIKE '43%') 
             OR (icd_version = 10 AND (icd_code LIKE 'G45%' OR icd_code LIKE 'I6%')) THEN 1
        WHEN (icd_version = 9 AND icd_code LIKE '290%') 
             OR (icd_version = 10 AND icd_code LIKE 'F0%') THEN 1
        WHEN (icd_version = 9 AND (icd_code LIKE '490%' OR icd_code LIKE '491%' OR icd_code LIKE '492%' OR icd_code LIKE '493%' OR icd_code LIKE '494%' OR icd_code LIKE '495%' OR icd_code LIKE '496%' OR icd_code LIKE '500%' OR icd_code LIKE '501%' OR icd_code LIKE '502%' OR icd_code LIKE '503%' OR icd_code LIKE '504%' OR icd_code LIKE '505%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'J4%' OR icd_code LIKE 'J6%' OR icd_code LIKE 'J7%' OR icd_code = 'I278' OR icd_code = 'I279' OR icd_code LIKE 'J684%' OR icd_code LIKE 'J701%' OR icd_code LIKE 'J703%')) THEN 1
        WHEN (icd_version = 9 AND (icd_code LIKE '710%' OR icd_code LIKE '714%' OR icd_code LIKE '725%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'M05%' OR icd_code LIKE 'M06%' OR icd_code LIKE 'M315%' OR icd_code LIKE 'M32%' OR icd_code LIKE 'M33%' OR icd_code LIKE 'M34%' OR icd_code LIKE 'M351%' OR icd_code LIKE 'M353%' OR icd_code LIKE 'M360%')) THEN 1
        WHEN (icd_version = 9 AND (icd_code LIKE '531%' OR icd_code LIKE '532%' OR icd_code LIKE '533%' OR icd_code LIKE '534%') 
             OR (icd_version = 10 AND (icd_code LIKE 'K25%' OR icd_code LIKE 'K26%' OR icd_code LIKE 'K27%' OR icd_code LIKE 'K28%')) THEN 1
        WHEN (icd_version = 9 AND (icd_code LIKE '570%' OR icd_code LIKE '571%' OR icd_code = '5733' OR icd_code = '5734' OR icd_code = '5738' OR icd_code = '5739' OR icd_code LIKE 'V427%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'B18%' OR icd_code LIKE 'K73%' OR icd_code LIKE 'K74%' OR icd_code = 'K700' OR icd_code = 'K701' OR icd_code = 'K702' OR icd_code = 'K703' OR icd_code = 'K709' OR icd_code = 'K713' OR icd_code = 'K714' OR icd_code = 'K715' OR icd_code = 'K717' OR icd_code LIKE 'K760%' OR icd_code = 'K762' OR icd_code = 'K763' OR icd_code = 'K764' OR icd_code = 'K768' OR icd_code = 'K769' OR icd_code = 'Z944')) THEN 1
        WHEN (icd_version = 9 AND (icd_code LIKE '2500%' OR icd_code LIKE '2501%' OR icd_code LIKE '2502%' OR icd_code LIKE '2503%' OR icd_code LIKE '2508%' OR icd_code LIKE '2509%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%') AND icd_code NOT LIKE '%0' AND icd_code NOT LIKE '%1' AND icd_code NOT LIKE '%3') THEN 1
        WHEN (icd_version = 9 AND (icd_code LIKE '2504%' OR icd_code LIKE '2505%' OR icd_code LIKE '2506%' OR icd_code LIKE '2507%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%') AND (icd_code LIKE '%2' OR icd_code LIKE '%4' OR icd_code LIKE '%5' OR icd_code LIKE '%6' OR icd_code LIKE '%7' OR icd_code LIKE '%8')) THEN 2
        WHEN (icd_version = 9 AND (icd_code LIKE '3441%' OR icd_code LIKE '342%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'G81%' OR icd_code LIKE 'G82%' OR icd_code LIKE 'G041%' OR icd_code LIKE 'G114%' OR icd_code LIKE 'G801%' OR icd_code LIKE 'G802%' OR icd_code LIKE 'G830%' OR icd_code LIKE 'G831%' OR icd_code LIKE 'G832%' OR icd_code LIKE 'G833%' OR icd_code LIKE 'G834%' OR icd_code = 'G839')) THEN 2
        WHEN (icd_version = 9 AND (icd_code LIKE '403%' OR icd_code LIKE '404%' OR icd_code LIKE '582%' OR icd_code LIKE '583%' OR icd_code LIKE '585%' OR icd_code LIKE '586%' OR icd_code LIKE '588%' OR icd_code = 'V420' OR icd_code = 'V451' OR icd_code LIKE 'V56%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'I12%' OR icd_code LIKE 'I13%' OR icd_code LIKE 'N03%' OR icd_code LIKE 'N05%' OR icd_code LIKE 'N18%' OR icd_code LIKE 'N19%' OR icd_code LIKE 'N25%' OR icd_code = 'Z490' OR icd_code = 'Z491' OR icd_code = 'Z492' OR icd_code = 'Z940' OR icd_code = 'Z992')) THEN 2
        WHEN (icd_version = 9 AND (icd_code LIKE '14%' OR icd_code LIKE '15%' OR icd_code LIKE '16%' OR icd_code LIKE '17%' OR icd_code LIKE '18%' OR icd_code LIKE '19%' OR icd_code LIKE '20%' OR icd_code LIKE '2386%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'C%' OR icd_code LIKE 'D0%' OR icd_code LIKE 'D37%' OR icd_code LIKE 'D38%' OR icd_code LIKE 'D39%' OR icd_code LIKE 'D4%') AND icd_code NOT LIKE 'D3%' AND icd_code NOT LIKE 'D41%') THEN 2
        WHEN (icd_version = 9 AND (icd_code LIKE '4560%' OR icd_code LIKE '4561%' OR icd_code LIKE '4562%' OR icd_code = '5722' OR icd_code = '5723' OR icd_code = '5724' OR icd_code = '5728' OR icd_code = '5735')) 
             OR (icd_version = 10 AND (icd_code LIKE 'I85%' OR icd_code LIKE 'I864%' OR icd_code LIKE 'I982%' OR icd_code LIKE 'K704%' OR icd_code LIKE 'K711%' OR icd_code LIKE 'K721%' OR icd_code LIKE 'K729%' OR icd_code LIKE 'K765%' OR icd_code LIKE 'K766%' OR icd_code LIKE 'K767%')) THEN 3
        WHEN (icd_version = 9 AND (icd_code LIKE '196%' OR icd_code LIKE '197%' OR icd_code LIKE '198%' OR icd_code LIKE '199%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'C77%' OR icd_code LIKE 'C78%' OR icd_code LIKE 'C79%' OR icd_code LIKE 'C80%')) THEN 6
        WHEN (icd_version = 9 AND (icd_code LIKE '042%' OR icd_code LIKE '043%' OR icd_code LIKE '044%')) 
             OR (icd_version = 10 AND (icd_code LIKE 'B20%' OR icd_code LIKE 'B21%' OR icd_code LIKE 'B22%' OR icd_code LIKE 'B24%')) THEN 6
        ELSE 0
      END AS weight
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  )
  GROUP BY hadm_id
),
cohort_with_charlson AS (
  SELECT
    c.*,
    COALESCE(cm.charlson_score, 0) AS charlson_score,
    CASE
      WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN c.los_days BETWEEN 4 AND 7 THEN '4-7'
      WHEN c.los_days >= 8 THEN '>=8'
    END AS los_group,
    CASE
      WHEN COALESCE(cm.charlson_score, 0) <= 3 THEN '<=3'
      WHEN COALESCE(cm.charlson_score, 0) BETWEEN 4 AND 5 THEN '4-5'
      WHEN COALESCE(cm.charlson_score, 0) > 5 THEN '>5'
    END AS charlson_group
  FROM cohort c
  LEFT JOIN charlson_map cm
    ON c.hadm_id = cm.hadm_id
)
SELECT
  CASE
    WHEN discharge_location = 'HOME' THEN 'Home'
    WHEN discharge_location IN ('REHAB', 'REHABILITATION') THEN 'Rehab'
    WHEN discharge_location IN ('SKILLED NURSING FACILITY', 'SNF') THEN 'SNF'
    WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
    ELSE 'Other'
  END AS discharge_destination,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM cohort_with_charlson), 2) AS pct
FROM cohort_with_charlson
GROUP BY discharge_destination
ORDER BY count DESC;