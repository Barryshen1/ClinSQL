WITH
  -- 1. Define the Cohort: 60-70 year old female patients with T2DM and HF during their hospital admission that led to an ICU stay.
  cohort_patients AS (
    SELECT DISTINCT
      p.subject_id,
      ad.hadm_id,
      icu.stay_id,
      icu.intime,
      icu.outtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` ad
      ON p.subject_id = ad.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON ad.hadm_id = icu.hadm_id AND p.subject_id = icu.subject_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 60 AND 70
      -- Check for Type 2 Diabetes Mellitus (T2DM)
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_dm
        WHERE
          di_dm.subject_id = ad.subject_id
          AND di_dm.hadm_id = ad.hadm_id
          AND (
            (di_dm.icd_version = 10 AND di_dm.icd_code LIKE 'E11%') OR -- ICD-10 Type 2 Diabetes Mellitus
            (di_dm.icd_version = 9 AND di_dm.icd_code LIKE '250%')    -- ICD-9 Diabetes Mellitus (general, E11 is specific to T2DM)
          )
      )
      -- Check for Heart Failure (HF)
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_hf
        WHERE
          di_hf.subject_id = ad.subject_id
          AND di_hf.hadm_id = ad.hadm_id
          AND (
            (di_hf.icd_version = 10 AND di_hf.icd_code LIKE 'I50%') OR -- ICD-10 Heart Failure
            (di_hf.icd_version = 9 AND di_hf.icd_code LIKE '428%')    -- ICD-9 Heart Failure
          )
      )
  ),
  -- 2. Define medication categories and map common drug names
  medication_mapping AS (
    SELECT 'Antidiabetics' AS drug_category, ['METFORMIN', 'INSULIN', 'GLIPIZIDE', 'GLYBURIDE', 'SITAGLIPTIN', 'CANAGLIFLOZIN', 'EMPAGLIFLOZIN', 'SEMAGLUTIDE', 'LIRAGLUTIDE', 'PRAMLINTIDE', 'PIOGLITAZONE', 'ROSIGLITAZONE', 'ACARBOSE', 'MIGLITOL', 'NATEGLINIDE', 'REPAGLINIDE', 'EXENATIDE', 'DULAGLUTIDE', 'ALBIGLUTIDE', 'LIXISENATIDE', 'SAXAGLIPTIN', 'LINAGLIPTIN', 'ALOGLIPTIN'] AS common_drugs
    UNION ALL SELECT 'Beta-blockers', ['METOPROLOL', 'CARVEDILOL', 'LABETALOL', 'ATENOLOL', 'PROPRANOLOL', 'BISOPROLOL', 'NADOLOL', 'ESMOLOL', 'SOTALOL', 'NEBIVOLOL', 'PINOBLOL', 'CELIPROLOL', 'BETAXOLOL'] AS common_drugs -- Added more types.
    UNION ALL SELECT 'ACEi/ARB/ARNI', ['LISINOPRIL', 'ENALAPRIL', 'RAMIPRIL', 'CAPTOPRIL', 'PERINDOPRIL', 'TRANDOLAPRIL', 'QUINAPRIL', 'FOSINOPRIL', 'BENACEPRIL', 'MOEXIPRIL', 'VALSARTAN', 'LOSARTAN', 'CANDESARTAN', 'IRBESARTAN', 'TELMISARTAN', 'OLMESARTAN', 'AZILSARTAN', 'EPROSARTAN', 'SACUBITRIL / VALSARTAN', 'ENTRESTO'] AS common_drugs -- Added more types.
    UNION ALL SELECT 'Loop Diuretics', ['FUROSEMIDE', 'BUMETANIDE', 'TORSEMIDE', 'ETHACRYNIC ACID'] AS common_drugs
  ),
  -- 3. Identify medication orders for cohort patients that start within the time windows
  patient_med_events AS (
    SELECT
      cp.subject_id,
      cp.hadm_id,
      cp.stay_id,
      mm.drug_category,
      pres.starttime
    FROM
      cohort_patients cp
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
      ON cp.subject_id = pres.subject_id
      AND cp.hadm_id = pres.hadm_id
    CROSS JOIN
      medication_mapping mm
    WHERE
      UPPER(pres.drug) IN (SELECT * FROM UNNEST(mm.common_drugs))
      -- Criteria for "initiation": prescription starttime within the window
      AND (
          (pres.starttime >= cp.intime AND pres.starttime < DATETIME_ADD(cp.intime, INTERVAL 48 HOUR)) -- First 48h (exclusive end)
          OR
          (pres.starttime >= DATETIME_SUB(cp.outtime, INTERVAL 24 HOUR) AND pres.starttime < cp.outtime) -- Final 24h (exclusive end)
      )
  ),
  -- 4. Flag if a patient initiated any drug from a category in each window for each stay
  patient_med_initiation_flags AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        mm.drug_category,
        MAX(CASE WHEN pme.starttime >= c.intime AND pme.starttime < DATETIME_ADD(c.intime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS initiated_48h,
        MAX(CASE WHEN pme.starttime >= DATETIME_SUB(c.outtime, INTERVAL 24 HOUR) AND pme.starttime < c.outtime THEN 1 ELSE 0 END) AS initiated_final_24h
    FROM
        cohort_patients c
    CROSS JOIN
        medication_mapping mm -- Ensure all categories are considered for all patients
    LEFT JOIN
        patient_med_events pme
        ON c.subject_id = pme.subject_id
        AND c.hadm_id = pme.hadm_id
        AND c.stay_id = pme.stay_id
        AND mm.drug_category = pme.drug_category
    GROUP BY
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        mm.drug_category
  ),
  -- 5. Calculate total number of unique ICU stays in the cohort for percentage calculation
  total_cohort_stays AS (
    SELECT CAST(COUNT(DISTINCT stay_id) AS BIGNUMERIC) AS total_stays
    FROM cohort_patients
  ),
  -- 6. Sum up initiations per category across all cohort stays
  initiation_counts_summary AS (
    SELECT
        pmif.drug_category,
        SUM(pmif.initiated_48h) AS count_initiated_48h,
        SUM(pmif.initiated_final_24h) AS count_initiated_final_24h
    FROM
        patient_med_initiation_flags pmif
    GROUP BY
        pmif.drug_category
  )
-- 7. Calculate final percentages and absolute differences
SELECT
    ics.drug_category,
    ROUND( (ics.count_initiated_48h * 100.0 / tcs.total_stays), 2) AS initiation_percent_first_48h,
    ROUND( (ics.count_initiated_final_24h * 100.0 / tcs.total_stays), 2) AS initiation_percent_final_24h,
    ROUND( ((ics.count_initiated_48h * 100.0 / tcs.total_stays) - (ics.count_initiated_final_24h * 100.0 / tcs.total_stays)), 2) AS absolute_difference_pp
FROM
    initiation_counts_summary ics
CROSS JOIN
    total_cohort_stays tcs
ORDER BY
    ics.drug_category;