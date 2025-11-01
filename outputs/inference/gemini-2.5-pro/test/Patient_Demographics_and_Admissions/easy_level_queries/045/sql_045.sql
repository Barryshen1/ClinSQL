WITH pneumonia_admissions AS (
    -- Step 1: Identify all hospital admissions with a pneumonia diagnosis
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
        ON dx.icd_code = d_dx.icd_code
        AND dx.icd_version = d_dx.icd_version
    WHERE d_dx.long_title LIKE '%Pneumonia%'
),

first_icu_stays AS (
    -- Step 2: For the target patient cohort, find the first ICU stay
    -- of their first hospital admission that had a pneumonia diagnosis.
    SELECT
        icu.los,
        -- Rank ICU stays within a single hospital admission
        ROW_NUMBER() OVER(PARTITION BY adm.hadm_id ORDER BY icu.intime) AS icu_stay_rank
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN (
        -- Subquery to rank hospital admissions for each patient
        SELECT
            hadm_id,
            subject_id,
            ROW_NUMBER() OVER(PARTITION BY subject_id ORDER BY admittime) AS admission_rank
        FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    ) AS adm
        ON pat.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON adm.hadm_id = icu.hadm_id
    -- Ensure the admission had a pneumonia diagnosis
    INNER JOIN pneumonia_admissions AS pa
        ON adm.hadm_id = pa.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 51 AND 61
        AND adm.admission_rank = 1 -- Filter for the first hospital admission
)

-- Step 3: Calculate the 25th percentile of ICU LOS from the filtered stays
SELECT
    APPROX_QUANTILES(los, 100)[OFFSET(25)] AS p25_icu_los_days
FROM first_icu_stays
WHERE
    icu_stay_rank = 1; -- Filter for the first ICU stay of that admission;