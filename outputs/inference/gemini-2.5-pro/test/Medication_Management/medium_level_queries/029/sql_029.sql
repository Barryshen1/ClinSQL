WITH
  -- Step 1: Define the patient cohort
  -- Women aged 69-79 with both T2DM and Heart Failure diagnoses
  cohort_hadm AS (
    SELECT
      dx.subject_id,
      dx.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON p.subject_id = dx.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
      ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 69 AND 79
      AND (
        LOWER(d.long_title) LIKE '%type 2 diabetes mellitus%'
        OR LOWER(d.long_title) LIKE '%heart failure%'
      )
    GROUP BY
      dx.subject_id,
      dx.hadm_id
    HAVING -- The patient must have a diagnosis for BOTH conditions in the same admission
      MAX(CASE WHEN LOWER(d.long_title) LIKE '%type 2 diabetes mellitus%' THEN 1 ELSE 0 END) = 1
      AND MAX(CASE WHEN LOWER(d.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) = 1
  ),
  -- Add admission and discharge times to the cohort
  final_cohort AS (
    SELECT
      c.subject_id,
      c.hadm_id,
      a.admittime,
      a.dischtime
    FROM cohort_hadm AS c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON c.hadm_id = a.hadm_id
  ),
  -- Step 2: Define the drug classes and their corresponding medication names/patterns
  drug_class_map AS (
    SELECT 'insulin' AS drug_pattern, 'Insulin' AS drug_class
    UNION ALL SELECT 'metformin', 'Metformin'
    UNION ALL SELECT 'glipizide', 'Sulfonylurea'
    UNION ALL SELECT 'glyburide', 'Sulfonylurea'
    UNION ALL SELECT 'glimepiride', 'Sulfonylurea'
    UNION ALL SELECT 'sitagliptin', 'DPP-4'
    UNION ALL SELECT 'saxagliptin', 'DPP-4'
    UNION ALL SELECT 'linagliptin', 'DPP-4'
    UNION ALL SELECT 'alogliptin', 'DPP-4'
    UNION ALL SELECT 'januvia', 'DPP-4'
    UNION ALL SELECT 'canagliflozin', 'SGLT2'
    UNION ALL SELECT 'dapagliflozin', 'SGLT2'
    UNION ALL SELECT 'empagliflozin', 'SGLT2'
    UNION ALL SELECT 'jardiance', 'SGLT2'
    UNION ALL SELECT 'exenatide', 'GLP-1'
    UNION ALL SELECT 'liraglutide', 'GLP-1'
    UNION ALL SELECT 'semaglutide', 'GLP-1'
    UNION ALL SELECT 'dulaglutide', 'GLP-1'
    UNION ALL SELECT 'pioglitazone', 'TZD'
    UNION ALL SELECT 'rosiglitazone', 'TZD'
  ),
  -- Combine medication administrations from both EMAR (hospital) and InputEvents (ICU)
  all_meds AS (
    SELECT hadm_id, charttime AS admin_time, medication AS med_name FROM `physionet-data.mimiciv_3_1_hosp.emar`
    UNION ALL
    SELECT i.hadm_id, i.starttime AS admin_time, d.label AS med_name
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` AS i
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS d
      ON i.itemid = d.itemid
  ),
  -- Link administrations to our cohort and classify them
  cohort_meds AS (
    SELECT
      fc.subject_id,
      fc.admittime,
      fc.dischtime,
      med.admin_time,
      dcm.drug_class
    FROM final_cohort AS fc
    INNER JOIN all_meds AS med
      ON fc.hadm_id = med.hadm_id
    INNER JOIN drug_class_map AS dcm
      ON LOWER(med.med_name) LIKE '%' || dcm.drug_pattern || '%'
  ),
  -- Step 3: Identify which patients received which drug class in each 72-hour window
  meds_in_window AS (
    SELECT
      cm.subject_id,
      cm.drug_class,
      MAX(
        CASE
          WHEN cm.admin_time BETWEEN cm.admittime AND DATETIME_ADD(cm.admittime, INTERVAL 72 HOUR)
            THEN 1
          ELSE 0
        END
      ) AS given_first_72h,
      MAX(
        CASE
          WHEN cm.admin_time BETWEEN DATETIME_SUB(cm.dischtime, INTERVAL 72 HOUR) AND cm.dischtime
            THEN 1
          ELSE 0
        END
      ) AS given_last_72h
    FROM cohort_meds AS cm
    GROUP BY
      cm.subject_id,
      cm.drug_class
  ),
  -- Step 4: Calculate the final percentages
  -- Count total unique patients in the cohort for the denominator
  total_patients AS (
    SELECT COUNT(DISTINCT subject_id) AS total_count
    FROM final_cohort
  )
-- Aggregate results and calculate percentages
SELECT
  d.drug_class,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN miw.given_first_72h = 1 THEN miw.subject_id END),
    tp.total_count
  ) * 100 AS percent_first_72h,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN miw.given_last_72h = 1 THEN miw.subject_id END),
    tp.total_count
  ) * 100 AS percent_last_72h
FROM (SELECT DISTINCT drug_class FROM drug_class_map) AS d
LEFT JOIN meds_in_window AS miw
  ON d.drug_class = miw.drug_class
CROSS JOIN total_patients AS tp
GROUP BY
  d.drug_class,
  tp.total_count
ORDER BY
  d.drug_class;