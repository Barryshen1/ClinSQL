WITH dvt_codes AS (
    -- Step 1: Identify all ICD codes related to Deep Vein Thrombosis (DVT).
    SELECT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE REGEXP_CONTAINS(LOWER(long_title), 'deep (vein|venous) thrombosis')
),

cohort AS (
    -- Step 2: Define the patient cohort: male, aged 42-52 at admission, with a DVT diagnosis.
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    INNER JOIN dvt_codes AS dvt
        ON dx.icd_code = dvt.icd_code AND dx.icd_version = dvt.icd_version
    WHERE
        pat.gender = 'M'
        -- Calculate age at admission and filter for the 42-52 range.
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 42 AND 52
),

lab_instability AS (
    -- Step 3: Calculate the "lab instability score" for each admission in the cohort.
    -- The score is the count of abnormal labs in the first 72 hours.
    SELECT
        c.hadm_id,
        c.admittime,
        c.dischtime,
        c.hospital_expire_flag,
        COUNT(le.labevent_id) AS lab_instability_score
    FROM cohort AS c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON c.hadm_id = le.hadm_id
        -- Filter labs to the first 72 hours of the admission.
        AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
        -- An abnormal lab is defined as a numeric value outside the normal reference range.
        AND le.valuenum IS NOT NULL
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
    GROUP BY
        c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),

percentile_threshold AS (
    -- Step 4: Determine the 95th percentile of the lab instability score for the cohort.
    SELECT
        APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(95)] AS p95_score
    FROM lab_instability
),

high_risk_group AS (
    -- Step 5: Identify the admissions that fall into the high-risk group (score >= 95th percentile).
    SELECT
        li.hadm_id,
        li.admittime,
        li.dischtime,
        li.hospital_expire_flag
    FROM lab_instability AS li
    CROSS JOIN percentile_threshold AS pt
    WHERE li.lab_instability_score >= pt.p95_score
),

high_risk_group_stats AS (
    -- Step 6: Calculate mortality and mean length of stay for the high-risk group.
    SELECT
        AVG(CAST(hospital_expire_flag AS FLOAT64)) AS high_risk_mortality_rate,
        AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS high_risk_mean_los_days,
        COUNT(DISTINCT hadm_id) AS high_risk_patient_count
    FROM high_risk_group
),

critical_lab_rates AS (
    -- Step 7: Calculate the rate of "critical" labs (flag = 'abnormal') for both the
    -- high-risk group and a baseline of all inpatients within the first 72 hours.
    SELECT
        SAFE_DIVIDE(
            COUNTIF(le.flag = 'abnormal' AND hrg.hadm_id IS NOT NULL),
            COUNTIF(hrg.hadm_id IS NOT NULL)
        ) AS high_risk_critical_lab_rate,
        SAFE_DIVIDE(
            COUNTIF(le.flag = 'abnormal'),
            COUNT(le.labevent_id)
        ) AS baseline_critical_lab_rate
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON adm.hadm_id = le.hadm_id
    -- Use a LEFT JOIN to flag labs belonging to the high-risk group.
    LEFT JOIN high_risk_group AS hrg
        ON le.hadm_id = hrg.hadm_id
    -- Filter all labs to the first 72 hours of their respective admissions.
    WHERE
        le.charttime BETWEEN adm.admittime AND TIMESTAMP_ADD(adm.admittime, INTERVAL 72 HOUR)
)

-- Final Step: Combine all calculated metrics into a single report.
SELECT
    pt.p95_score AS lab_instability_95th_percentile,
    s.high_risk_patient_count,
    s.high_risk_mortality_rate,
    s.high_risk_mean_los_days,
    cr.high_risk_critical_lab_rate,
    cr.baseline_critical_lab_rate
FROM percentile_threshold AS pt,
     high_risk_group_stats AS s,
     critical_lab_rates AS cr;