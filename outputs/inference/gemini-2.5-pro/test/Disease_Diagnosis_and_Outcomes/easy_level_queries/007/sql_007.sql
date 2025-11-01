WITH ugib_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        seq_num = 1 -- Filter for primary diagnoses
        AND
        (
            -- ICD-9 codes for UGIB
            (icd_version = 9 AND (
                icd_code IN ('5780', '5781', '5789') OR -- Hematemesis, Melena, GIH unspecified
                STARTS_WITH(icd_code, '5310') OR -- Gastric ulcer with hemorrhage
                STARTS_WITH(icd_code, '5312') OR -- Gastric ulcer with hemorrhage and perf
                STARTS_WITH(icd_code, '5314') OR -- Chronic Gastric ulcer with hemorrhage
                STARTS_WITH(icd_code, '5316') OR -- Chronic Gastric ulcer with hemorrhage and perf
                STARTS_WITH(icd_code, '5320') OR -- Duodenal ulcer with hemorrhage
                STARTS_WITH(icd_code, '5322') OR -- Duodenal ulcer with hemorrhage and perf
                STARTS_WITH(icd_code, '5324') OR -- Chronic Duodenal ulcer with hemorrhage
                STARTS_WITH(icd_code, '5326') OR -- Chronic Duodenal ulcer with hemorrhage and perf
                STARTS_WITH(icd_code, '5330') OR -- Peptic ulcer with hemorrhage
                STARTS_WITH(icd_code, '5332') OR -- Peptic ulcer with hemorrhage and perf
                STARTS_WITH(icd_code, '5334') OR -- Chronic Peptic ulcer with hemorrhage
                STARTS_WITH(icd_code, '5336') OR -- Chronic Peptic ulcer with hemorrhage and perf
                STARTS_WITH(icd_code, '5340') OR -- Gastrojejunal ulcer with hemorrhage
                STARTS_WITH(icd_code, '5342') OR -- Gastrojejunal ulcer with hemorrhage and perf
                STARTS_WITH(icd_code, '5344') OR -- Chronic Gastrojejunal ulcer with hemorrhage
                STARTS_WITH(icd_code, '5346')    -- Chronic Gastrojejunal ulcer with hemorrhage and perf
            ))
            OR
            -- ICD-10 codes for UGIB
            (icd_version = 10 AND (
                icd_code IN ('K920', 'K921', 'K922', 'K2901') OR -- Hematemesis, Melena, GIH unspecified, Acute gastritis w bleeding
                STARTS_WITH(icd_code, 'K250') OR -- Gastric ulcer with hemorrhage
                STARTS_WITH(icd_code, 'K252') OR -- Gastric ulcer with hemorrhage and perf
                STARTS_WITH(icd_code, 'K254') OR -- Chronic Gastric ulcer with hemorrhage
                STARTS_WITH(icd_code, 'K256') OR -- Chronic Gastric ulcer with hemorrhage and perf
                STARTS_WITH(icd_code, 'K260') OR -- Duodenal ulcer with hemorrhage
                STARTS_WITH(icd_code, 'K262') OR -- Duodenal ulcer with hemorrhage and perf
                STARTS_WITH(icd_code, 'K264') OR -- Chronic Duodenal ulcer with hemorrhage
                STARTS_WITH(icd_code, 'K266') OR -- Chronic Duodenal ulcer with hemorrhage and perf
                STARTS_WITH(icd_code, 'K270') OR -- Peptic ulcer with hemorrhage
                STARTS_WITH(icd_code, 'K272') OR -- Peptic ulcer with hemorrhage and perf
                STARTS_WITH(icd_code, 'K274') OR -- Chronic Peptic ulcer with hemorrhage
                STARTS_WITH(icd_code, 'K276') OR -- Chronic Peptic ulcer with hemorrhage and perf
                STARTS_WITH(icd_code, 'K280') OR -- Gastrojejunal ulcer with hemorrhage
                STARTS_WITH(icd_code, 'K282') OR -- Gastrojejunal ulcer with hemorrhage and perf
                STARTS_WITH(icd_code, 'K284') OR -- Chronic Gastrojejunal ulcer with hemorrhage
                STARTS_WITH(icd_code, 'K286')    -- Chronic Gastrojejunal ulcer with hemorrhage and perf
            ))
        )
),

-- CTE to define the final cohort and calculate length of stay for each admission
cohort AS (
    SELECT
        -- Calculate hospital LOS in fractional days for precision
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    -- Restrict to admissions with a primary UGIB diagnosis
    INNER JOIN ugib_admissions
        ON adm.hadm_id = ugib_admissions.hadm_id
    WHERE
        -- Filter for female patients
        pat.gender = 'F'
        -- Calculate age at admission and filter for the 84-94 age range
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 84 AND 94
        -- Ensure LOS is a positive value
        AND adm.dischtime > adm.admittime
)

-- Final aggregation to calculate the IQR of the hospital length of stay
SELECT
    -- APPROX_QUANTILES(los_days, 4) returns an array [min, q1, median, q3, max]
    -- We subtract the 25th percentile (index 1) from the 75th percentile (index 3)
    (
        APPROX_QUANTILES(los_days, 4)[OFFSET(3)] - APPROX_QUANTILES(los_days, 4)[OFFSET(1)]
    ) AS hospital_los_iqr_days
FROM
    cohort;