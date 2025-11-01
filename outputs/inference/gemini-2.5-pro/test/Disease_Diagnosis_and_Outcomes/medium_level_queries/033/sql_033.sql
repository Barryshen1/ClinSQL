WITH
-- Step 1: Define the base patient population (male, 82-92 years old)
base_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
      AND anchor_age BETWEEN 82 AND 92
),

-- Step 2: Identify hospital admissions for these patients that involved a procedure
proc_admissions AS (
    SELECT DISTINCT adm.subject_id, adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN base_patients AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
        ON adm.hadm_id = proc.hadm_id
),

-- Step 3: Filter for admissions that have a postoperative complication diagnosis.
-- These are the final admissions we will analyze.
final_hadm_ids AS (
    SELECT DISTINCT pa.hadm_id
    FROM proc_admissions AS pa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON pa.hadm_id = dx.hadm_id
    WHERE
        -- ICD-9 codes for complications of surgical and medical care
        (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN '996' AND '999')
        -- ICD-10 codes for complications of surgical and medical care
        OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'T80' AND 'T88')
),

-- Step 4: Calculate the number of comorbidities for each admission in our cohort.
-- A comorbidity is any diagnosis that is NOT a postoperative complication.
comorbidity_counts AS (
    SELECT
        dx.hadm_id,
        COUNT(DISTINCT dx.icd_code) AS comorbidity_count
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    INNER JOIN final_hadm_ids fh ON dx.hadm_id = fh.hadm_id
    WHERE
        NOT (
            (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN '996' AND '999')
            OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'T80' AND 'T88')
        )
    GROUP BY dx.hadm_id
),

-- Step 5: Assemble the final cohort data with all necessary flags and categories
cohort_data AS (
    SELECT
        adm.hadm_id,
        adm.hospital_expire_flag,
        -- Categorize as ICU if there's any ICU stay associated with the hadm_id
        CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
        -- Categorize hospital LOS
        CASE
            WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) <= 5 THEN 'LOS <= 5'
            ELSE 'LOS > 5'
        END AS los_category,
        -- Use COALESCE for admissions that might have no comorbidities other than the complication
        COALESCE(cc.comorbidity_count, 0) AS comorbidity_count,
        -- Create comorbidity bins
        CASE
            WHEN COALESCE(cc.comorbidity_count, 0) <= 1 THEN '0-1'
            WHEN COALESCE(cc.comorbidity_count, 0) = 2 THEN '2'
            ELSE '>=3'
        END AS comorbidity_bin
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    -- Ensure we only include the admissions we identified in our cohort
    INNER JOIN final_hadm_ids AS fh
        ON adm.hadm_id = fh.hadm_id
    -- Left join to check for an ICU stay
    LEFT JOIN (SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`) AS icu
        ON adm.hadm_id = icu.hadm_id
    -- Left join to get the comorbidity count
    LEFT JOIN comorbidity_counts AS cc
        ON adm.hadm_id = cc.hadm_id
)

-- Step 6: Final aggregation and reporting
SELECT
    icu_status,
    los_category,
    comorbidity_bin,
    COUNT(hadm_id) AS N,
    -- Round the percentage for cleaner output
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
    ROUND(AVG(comorbidity_count), 2) AS avg_comorbidity_count
FROM cohort_data
GROUP BY
    icu_status,
    los_category,
    comorbidity_bin
ORDER BY
    icu_status DESC,
    los_category,
    comorbidity_bin;