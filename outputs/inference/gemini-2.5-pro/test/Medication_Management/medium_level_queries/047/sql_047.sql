WITH
  -- Step 1: Identify the cohort of male inpatients aged 40-50 with both diabetes and heart failure.
  cohort_hadms AS (
    SELECT
      pat.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON pat.subject_id = adm.subject_id
    -- Join to diagnoses to filter by condition
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    WHERE
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 40 AND 50
    GROUP BY
      pat.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    HAVING
      -- Must have a diagnosis for Diabetes
      COUNT(
        DISTINCT CASE
          WHEN dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) = '250'
            THEN 1
          WHEN dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('E08', 'E09', 'E10', 'E11', 'E13')
            THEN 1
        END
      ) > 0
      AND
      -- Must also have a diagnosis for Heart Failure
      COUNT(
        DISTINCT CASE
          WHEN dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) = '428'
            THEN 1
          WHEN dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) = 'I50'
            THEN 1
        END
      ) > 0
  ),
  -- Step 2: For each patient, identify relevant medications and flag if they were active in the first/last 24h.
  medication_periods AS (
    SELECT
      cohort.hadm_id,
      -- Classify drugs into the desired categories
      CASE
        WHEN LOWER(pr.drug) LIKE '%insulin%' OR LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' OR LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%dulaglutide%'
          THEN 'Antidiabetic'
        WHEN LOWER(pr.drug) LIKE '%metoprolol%' OR LOWER(pr.drug) LIKE '%carvedilol%' OR LOWER(pr.drug) LIKE '%bisoprolol%' OR LOWER(pr.drug) LIKE '%atenolol%' OR LOWER(pr.drug) LIKE '%propranolol%' OR LOWER(pr.drug) LIKE '%labetalol%' OR LOWER(pr.drug) LIKE '%esmolol%' OR LOWER(pr.drug) LIKE '%nebivolol%'
          THEN 'Beta-Blocker'
        WHEN LOWER(pr.drug) LIKE '%lisinopril%' OR LOWER(pr.drug) LIKE '%enalapril%' OR LOWER(pr.drug) LIKE '%ramipril%' OR LOWER(pr.drug) LIKE '%captopril%' OR LOWER(pr.drug) LIKE '%benazepril%' OR LOWER(pr.drug) LIKE '%losartan%' OR LOWER(pr.drug) LIKE '%valsartan%' OR LOWER(pr.drug) LIKE '%irbesartan%' OR LOWER(pr.drug) LIKE '%olmesartan%' OR LOWER(pr.drug) LIKE '%candesartan%' OR LOWER(pr.drug) LIKE '%sacubitril%'
          THEN 'ACEi/ARB/ARNI'
        WHEN LOWER(pr.drug) LIKE '%furosemide%' OR LOWER(pr.drug) LIKE '%bumetanide%' OR LOWER(pr.drug) LIKE '%torsemide%'
          THEN 'Loop Diuretic'
      END AS med_class,
      -- Flag if prescription was active in the first 24 hours of admission
      (
        CASE
          WHEN pr.starttime <= DATETIME_ADD(cohort.admittime, INTERVAL 24 HOUR) AND pr.stoptime >= cohort.admittime
            THEN 1
          ELSE 0
        END
      ) AS on_first_24h,
      -- Flag if prescription was active in the last 24 hours before discharge
      (
        CASE
          WHEN pr.starttime <= cohort.dischtime AND pr.stoptime >= DATETIME_SUB(cohort.dischtime, INTERVAL 24 HOUR)
            THEN 1
          ELSE 0
        END
      ) AS on_last_24h
    FROM cohort_hadms AS cohort
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      ON cohort.hadm_id = pr.hadm_id
    WHERE
      pr.drug IS NOT NULL
  ),
  -- Step 3: Summarize at the patient-class level to see if they were on the drug class in each period.
  patient_med_summary AS (
    SELECT
      hadm_id,
      med_class,
      MAX(on_first_24h) AS is_on_first,
      MAX(on_last_24h) AS is_on_last
    FROM medication_periods
    WHERE
      med_class IS NOT NULL
    GROUP BY
      hadm_id,
      med_class
  ),
  -- Helper CTE to get the total number of patients in the cohort for percentage calculation.
  total_patients AS (
    SELECT
      COUNT(DISTINCT hadm_id) AS n
    FROM cohort_hadms
  )
-- Step 4: Final aggregation to calculate percentages and counts for each medication class.
SELECT
  pms.med_class,
  SAFE_DIVIDE(SUM(pms.is_on_first) * 100, MAX(tp.n)) AS pct_on_first_24h,
  SAFE_DIVIDE(SUM(pms.is_on_last) * 100, MAX(tp.n)) AS pct_on_last_24h,
  COUNTIF(pms.is_on_first = 1 AND pms.is_on_last = 1) AS count_continued,
  COUNTIF(pms.is_on_first = 0 AND pms.is_on_last = 1) AS count_initiated_late,
  COUNTIF(pms.is_on_first = 1 AND pms.is_on_last = 0) AS count_discontinued
FROM patient_med_summary AS pms
CROSS JOIN total_patients AS tp
GROUP BY
  pms.med_class
ORDER BY
  pms.med_class;