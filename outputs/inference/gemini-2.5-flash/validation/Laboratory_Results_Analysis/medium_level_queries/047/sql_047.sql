WITH admissions_filtered AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 67 AND 77
),
acs_admissions AS (
    SELECT DISTINCT
        af.subject_id,
        af.hadm_id,
        af.admittime
    FROM
        admissions_filtered AS af
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON af.hadm_id = diag.hadm_id
    WHERE
        (
            diag.icd_version = 9 AND (
                diag.icd_code LIKE '410%'   -- Acute myocardial infarction (e.g., 410.0-410.9)
                OR diag.icd_code = '4111'   -- Unstable angina
                OR diag.icd_code = '4118'   -- Other specified forms of acute ischemic heart disease (e.g., intermediate coronary syndrome)
                OR diag.icd_code LIKE '413%' -- Angina Pectoris (e.g., 413.0-413.9)
            )
        ) OR (
            diag.icd_version = 10 AND (
                diag.icd_code = 'I200'      -- Unstable angina
                OR diag.icd_code LIKE 'I21%'   -- Myocardial infarction (e.g., I21.0-I21.9)
                OR diag.icd_code LIKE 'I22%'   -- Subsequent myocardial infarction (e.g., I22.0-I22.9)
                OR diag.icd_code LIKE 'I24%'   -- Other acute ischemic heart diseases (e.g., I24.0-I24.9)
            )
        )
),
troponin_t_measurements AS (
    SELECT
        le.subject_id,
        le.hadm_id,
        le.charttime,
        le.valuenum
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN
        acs_admissions AS acs
        ON le.hadm_id = acs.hadm_id
    WHERE
        le.itemid = 51002 -- Itemid for Troponin T
        AND le.valuenum IS NOT NULL
        AND le.valuenum >= 0 -- Exclude erroneous negative values
        AND le.charttime >= acs.admittime -- Ensure measurement is during or after admission
),
initial_troponin_raw AS ( -- Identifies the first troponin measurement for each admission
    SELECT
        t.subject_id,
        t.hadm_id,
        t.valuenum,
        ROW_NUMBER() OVER (PARTITION BY t.hadm_id ORDER BY t.charttime ASC) AS rn
    FROM
        troponin_t_measurements AS t
),
filtered_initial_troponin AS ( -- Filters to only include the first measurement above the 99th percentile threshold
    SELECT
        it.subject_id,
        it.hadm_id,
        it.valuenum AS initial_troponin_t_value
    FROM
        initial_troponin_raw AS it
    WHERE
        it.rn = 1 -- Select the first measurement for each admission
        AND it.valuenum > 0.03 -- Apply the 99th percentile cutoff (common clinical threshold in ng/mL or ug/L)
)
-- Final aggregation to report patient/admission counts, mean, median, and IQR
SELECT
    COUNT(DISTINCT fit.subject_id) AS patient_count,
    COUNT(DISTINCT fit.hadm_id) AS admission_count,
    AVG(fit.initial_troponin_t_value) AS initial_troponin_mean,
    APPROX_QUANTILES(fit.initial_troponin_t_value, 100)[OFFSET(50)] AS initial_troponin_median,
    (APPROX_QUANTILES(fit.initial_troponin_t_value, 100)[OFFSET(75)] - APPROX_QUANTILES(fit.initial_troponin_t_value, 100)[OFFSET(25)]) AS initial_troponin_iqr
FROM
    filtered_initial_troponin AS fit;