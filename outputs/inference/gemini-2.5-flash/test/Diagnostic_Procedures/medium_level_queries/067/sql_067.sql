with demographics and hospital Length of Stay (LOS)
WITH admission_cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        pat.gender,
        pat.anchor_age,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_hospital
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 39 AND 49
        AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
),
-- 2. Identify Acute Coronary Syndrome (ACS) diagnoses and classify as primary/secondary
acs_diagnoses_filtered AS (
    SELECT
        di.subject_id,
        di.hadm_id,
        di.seq_num,
        di.icd_code,
        di.icd_version
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        -- Filter for common ACS ICD-9 and ICD-10 codes
        (
            (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '411%' OR di.icd_code LIKE '413%'))
            OR
            (di.icd_version = 10 AND (di.icd_code LIKE 'I20%' OR di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I24%'))
        )
),
acs_classification AS (
    SELECT
        hadm_id,
        -- Classify ACS: 'Primary ACS' if any ACS diagnosis has seq_num = 1, otherwise 'Secondary ACS'
        CASE
            WHEN MIN(seq_num) = 1 THEN 'Primary ACS'
            ELSE 'Secondary ACS'
        END AS acs_type
    FROM
        acs_diagnoses_filtered
    GROUP BY
        hadm_id
),
-- 3. Count ICU stays per admission for stratification
icu_stays_count AS (
    SELECT
        hadm_id,
        COUNT(DISTINCT stay_id) AS num_icu_stays
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY
        hadm_id
),
-- 4. Count ultrasound procedures (including echocardiograms) per admission
ultrasound_procedures AS (
    SELECT
        pr.hadm_id,
        COUNT(pr.icd_code) AS ultrasound_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
    WHERE
        -- Filter for ultrasound and echocardiogram procedures based on ICD version
        (
            (pr.icd_version = 9 AND pr.icd_code LIKE '88.7%') -- Diagnostic Ultrasound (ICD-9-CM Vol 3 Section 88.7)
            OR
            (pr.icd_version = 10 AND (dp.long_title LIKE '%ultrasound%' OR dp.long_title LIKE '%echo%')) -- Broad search for ICD-10 PCS using long_title
        )
    GROUP BY
        pr.hadm_id
)
-- 5. Combine all CTEs to form the final analytical cohort and calculate percentiles
SELECT
    final_cohort.acs_type,
    final_cohort.icu_stay_group,
    PERCENTILE_CONT(0.25) OVER (PARTITION BY final_cohort.acs_type, final_cohort.icu_stay_group) AS p25_ultrasound_count,
    PERCENTILE_CONT(0.50) OVER (PARTITION BY final_cohort.acs_type, final_cohort.icu_stay_group) AS p50_ultrasound_count,
    PERCENTILE_CONT(0.75) OVER (PARTITION BY final_cohort.acs_type, final_cohort.icu_stay_group) AS p75_ultrasound_count
FROM (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        acc.acs_type,
        -- Stratify by number of ICU stays
        CASE
            WHEN isc.num_icu_stays BETWEEN 1 AND 4 THEN '1-4 ICU Stays'
            WHEN isc.num_icu_stays BETWEEN 5 AND 7 THEN '5-7 ICU Stays'
            ELSE NULL -- Admissions outside this range will be filtered out
        END AS icu_stay_group,
        COALESCE(up.ultrasound_count, 0) AS ultrasound_count
    FROM
        admission_cohort ac
    INNER JOIN -- Only include admissions with an ACS diagnosis classification
        acs_classification acc ON ac.hadm_id = acc.hadm_id
    INNER JOIN -- Only include admissions with 1 to 7 ICU stays for stratification
        icu_stays_count isc ON ac.hadm_id = isc.hadm_id
    LEFT JOIN -- Include admissions even if they had no ultrasound procedures (count will be 0 due to COALESCE)
        ultrasound_procedures up ON ac.hadm_id = up.hadm_id
    WHERE
        isc.num_icu_stays BETWEEN 1 AND 7 -- Ensure ICU stays are within the specified range for stratification
        AND acc.acs_type IS NOT NULL -- Ensure ACS classification exists
) AS final_cohort
WHERE
    final_cohort.icu_stay_group IS NOT NULL -- Exclude admissions that do not fit into the 1-4 or 5-7 ICU stay groups
GROUP BY
    final_cohort.acs_type,
    final_cohort.icu_stay_group
ORDER BY
    final_cohort.acs_type,
    final_cohort.icu_stay_group;