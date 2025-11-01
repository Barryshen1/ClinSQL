WITH AdmissionsWithHF AS (
    -- CTE 1: Identify the target cohort (male, 43-53, with heart failure)
    -- and calculate basic admission details like LOS and hospital expire flag.
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.hospital_expire_flag,
        -- Calculate length of stay in days
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    INNER JOIN
        ( -- Subquery to find admissions with at least one heart failure diagnosis
            SELECT DISTINCT subject_id, hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE
                (icd_version = 9 AND icd_code LIKE '428%') OR -- ICD-9 codes for Heart Failure
                (icd_version = 10 AND icd_code LIKE 'I50%')    -- ICD-10 codes for Heart Failure
        ) hf_diag
        ON ad.subject_id = hf_diag.subject_id AND ad.hadm_id = hf_diag.hadm_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 43 AND 53
        -- Ensure LOS is non-negative and represents a valid completed admission period
        AND DATE_DIFF(ad.dischtime, ad.admittime, DAY) >= 0
),
AdmissionsWithComorbidityCounts AS (
    -- CTE 2: For each identified admission, count the number of distinct diagnoses
    -- to serve as a proxy for comorbidity burden.
    SELECT
        adhf.subject_id,
        adhf.hadm_id,
        adhf.hospital_expire_flag,
        adhf.los_days,
        COUNT(DISTINCT di.icd_code) AS num_diagnoses -- Calculate number of distinct diagnoses per hadm_id
    FROM
        AdmissionsWithHF adhf
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON adhf.subject_id = di.subject_id AND adhf.hadm_id = di.hadm_id
    GROUP BY
        adhf.subject_id,
        adhf.hadm_id,
        adhf.hospital_expire_flag,
        adhf.los_days
),
StratifiedAdmissions AS (
    -- CTE 3: Apply NTILE window functions to stratify admissions by LOS quartiles
    -- and comorbidity burden tertiles, now that `los_days` and `num_diagnoses` are computed per admission.
    SELECT
        subject_id,
        hadm_id,
        hospital_expire_flag,
        los_days,
        num_diagnoses,
        -- Assign LOS quartiles based on `los_days`
        NTILE(4) OVER (ORDER BY los_days) AS los_quartile_num,
        -- Assign comorbidity burden tertiles (Low/Medium/High) based on `num_diagnoses`
        CASE
            WHEN NTILE(3) OVER (ORDER BY num_diagnoses) = 1 THEN 'Low'
            WHEN NTILE(3) OVER (ORDER BY num_diagnoses) = 2 THEN 'Medium'
            WHEN NTILE(3) OVER (ORDER BY num_diagnoses) = 3 THEN 'High'
            ELSE 'Unknown' -- Should not happen if NTILE(3) always returns 1, 2, or 3
        END AS comorbidity_burden_category
    FROM
        AdmissionsWithComorbidityCounts
)
-- Final SELECT: Aggregate the stratified data to calculate mortality percentages.
SELECT
    FORMAT('Q%d', los_quartile_num) AS los_quartile, -- Format quartile number as "Q1", "Q2", etc.
    comorbidity_burden_category,
    COUNT(hadm_id) AS total_admissions, -- COUNT(DISTINCT hadm_id) is not needed as each row in StratifiedAdmissions is a unique hadm_id
    SUM(hospital_expire_flag) AS in_hospital_deaths,
    -- Calculate mortality percentage, handling division by zero
    ROUND(CAST(SUM(hospital_expire_flag) AS BIGNUMERIC) * 100 / NULLIF(COUNT(hadm_id), 0), 2) AS mortality_percentage
FROM
    StratifiedAdmissions
GROUP BY
    los_quartile_num,
    comorbidity_burden_category
ORDER BY
    los_quartile_num,
    -- Custom order for comorbidity burden categories
    CASE comorbidity_burden_category
        WHEN 'Low' THEN 1
        WHEN 'Medium' THEN 2
        WHEN 'High' THEN 3
        ELSE 4
    END;