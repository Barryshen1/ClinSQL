WITH AdmissionsHF AS (
        -- Step 1: Identify all unique ICD codes for Heart Failure (HF)
        -- This CTE defines the set of ICD codes that classify as Heart Failure.
        -- These codes will be used to filter the patient cohort and to exclude from comorbidity counts.
        SELECT DISTINCT icd_code, icd_version
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE (icd_version = 10 AND icd_code LIKE 'I50%') -- ICD-10 codes for Heart Failure
           OR (icd_version = 9 AND icd_code LIKE '428%')  -- ICD-9 codes for Heart Failure
    ),
    PatientCohortRaw AS (
        -- Step 2: Select the initial patient cohort based on age, gender, and HF diagnosis.
        -- This CTE gathers all admissions that meet the demographic and HF criteria.
        SELECT
            adm.subject_id,
            adm.hadm_id,
            adm.admittime,
            adm.dischtime,
            adm.hospital_expire_flag
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
        JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
            ON adm.subject_id = pat.subject_id
        WHERE pat.gender = 'M' -- Filter for male patients
          AND pat.anchor_age BETWEEN 72 AND 82 -- Filter for age range 72-82
          AND EXISTS ( -- Ensure the admission has at least one Heart Failure diagnosis during this admission
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_hf
                JOIN AdmissionsHF hf_codes
                    ON diag_hf.icd_code = hf_codes.icd_code
                   AND diag_hf.icd_version = hf_codes.icd_version
                WHERE diag_hf.hadm_id = adm.hadm_id
          )
    ),
    ComorbidityCounts AS (
        -- Step 3: Calculate the comorbidity count for each eligible admission.
        -- This CTE joins diagnoses to the cohort and counts diagnoses, *excluding* HF codes.
        SELECT
            pcr.hadm_id,
            COUNT(DISTINCT diag.icd_code) AS comorbidity_count
        FROM PatientCohortRaw pcr
        JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            ON pcr.hadm_id = diag.hadm_id
        LEFT JOIN AdmissionsHF hf_codes -- Left join to identify HF codes so they can be excluded
            ON diag.icd_code = hf_codes.icd_code
           AND diag.icd_version = hf_codes.icd_version
        WHERE hf_codes.icd_code IS NULL -- Exclude actual HF codes from the comorbidity count
        GROUP BY pcr.hadm_id
    ),
    AdmissionDetails AS (
    -- Step 4: Combine all necessary details for each admission: LOS, ICU status, mortality, comorbidity
    SELECT
        pcr.subject_id,
        pcr.hadm_id,
        TIMESTAMP_DIFF(pcr.dischtime, pcr.admittime, DAY) AS hospital_los_days, -- Calculate hospital length of stay in days
        pcr.hospital_expire_flag,
        CASE
            WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = pcr.hadm_id)
            THEN 'ICU' -- Admission had at least one ICU stay
            ELSE 'Non-ICU' -- Admission had no ICU stays
        END AS icu_status,
        COALESCE(cc.comorbidity_count, 0) AS comorbidity_count, -- Use COALESCE to set 0 for admissions with no non-HF comorbidities
        CASE -- Define LOS categories for grouping
            WHEN TIMESTAMP_DIFF(pcr.dischtime, pcr.admittime, DAY) <= 3 THEN 'LOS <= 3 days'
            WHEN TIMESTAMP_DIFF(pcr.dischtime, pcr.admittime, DAY) BETWEEN 4 AND 6 THEN 'LOS 4-6 days'
            WHEN TIMESTAMP_DIFF(pcr.dischtime, pcr.admittime, DAY) BETWEEN 7 AND 10 THEN 'LOS 7-10 days'
            ELSE 'LOS > 10 days'
        END AS los_category
    FROM PatientCohortRaw pcr
    LEFT JOIN ComorbidityCounts cc
        ON pcr.hadm_id = cc.hadm_id
    )
-- Final SELECT statement to present the results
SELECT
    ad.icu_status,
    ad.los_category,
    -- In-hospital mortality: count deaths / total admissions, expressed as a rate
    SUM(CASE WHEN ad.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality_count,
    COUNT(ad.hadm_id) AS total_admissions,
    SAFE_DIVIDE(SUM(CASE WHEN ad.hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(ad.hadm_id)) AS mortality_rate,
    APPROX_QUANTILES(ad.hospital_los_days, 2)[OFFSET(1)] AS median_los_days, -- Median LOS using APPROX_QUANTILES
    AVG(ad.comorbidity_count) AS avg_comorbidity_count
FROM AdmissionDetails ad
GROUP BY ad.icu_status, ad.los_category
ORDER BY ad.icu_status,
         CASE
             WHEN ad.los_category = 'LOS <= 3 days' THEN 1
             WHEN ad.los_category = 'LOS 4-6 days' THEN 2
             WHEN ad.los_category = 'LOS 7-10 days' THEN 3
             WHEN ad.los_category = 'LOS > 10 days' THEN 4
             ELSE 99
         END; -- Order LOS categories numerically for consistent output;