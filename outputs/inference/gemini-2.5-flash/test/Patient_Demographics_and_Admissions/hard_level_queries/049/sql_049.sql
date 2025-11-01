WITH CohortAdmissions AS (
    -- Select eligible admissions based on demographic, administrative, and diagnostic criteria
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
    WHERE
        pat.gender = 'F'
        AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 61 AND 71
        AND adm.insurance = 'Medicare'
        AND adm.admission_location = 'SKILLED NURSING FACILITY (SNF)'
        AND diag.seq_num = 1 -- Principal diagnosis
        AND (diag.icd_code LIKE '584%' OR diag.icd_code LIKE 'N17%') -- Acute Kidney Injury (ICD-9 codes like 584.x, ICD-10 codes like N17.x)
        -- Ensure that each hospital admission is counted once, even if multiple diagnosis codes match the criteria (e.g., if different ICD versions are present).
        QUALIFY ROW_NUMBER() OVER (PARTITION BY adm.hadm_id ORDER BY diag.icd_version DESC, diag.icd_code) = 1
),
CohortWithNextAdmission AS (
    -- For each admission in the cohort, find the next admission time for the same patient
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        ca.los_days,
        ca.hospital_expire_flag,
        -- Get the admission time of the subsequent admission for the same patient
        LEAD(ca.admittime, 1) OVER (PARTITION BY ca.subject_id ORDER BY ca.admittime) AS next_admittime
    FROM
        CohortAdmissions AS ca
),
FinalCohortMetrics AS (
    -- Determine 30-day readmission status for patients discharged alive from the index stay
    SELECT
        cna.subject_id,
        cna.hadm_id,
        cna.los_days,
        -- An admission is considered for readmission if the patient is discharged alive.
        -- A readmission occurs if the subsequent admission date is within 30 days *after*
        -- the discharge date of the current (index) admission.
        CASE
            WHEN cna.hospital_expire_flag = 0  -- Patient was discharged alive from index hospital stay
                AND cna.next_admittime IS NOT NULL
                AND DATE_DIFF(cna.next_admittime, cna.dischtime, DAY) > 0  -- Must be strictly after discharge
                AND DATE_DIFF(cna.next_admittime, cna.dischtime, DAY) <= 30
            THEN TRUE
            ELSE FALSE
        END AS readmitted_30_day
    FROM
        CohortWithNextAdmission AS cna
    WHERE
        cna.hospital_expire_flag = 0 -- Crucially, exclude patients who died during the index admission from readmission analysis.
)
-- Final aggregation to calculate all requested metrics
SELECT
    COUNT(fc.hadm_id) AS total_index_admissions_eligible_for_metrics,
    -- 30-day readmission rate
    SAFE_DIVIDE(SUM(CASE WHEN fc.readmitted_30_day THEN 1 ELSE 0 END), COUNT(fc.hadm_id)) * 100 AS readmission_rate_30_day_percent,
    -- Median index LOS for readmitted patients (using a subquery to aggregate)
    (SELECT APPROX_QUANTILES(fc_med.los_days, 2)[OFFSET(1)]
     FROM FinalCohortMetrics AS fc_med
     WHERE fc_med.readmitted_30_day = TRUE) AS median_los_readmitted_days,
    -- Median index LOS for non-readmitted patients (using a subquery to aggregate)
    (SELECT APPROX_QUANTILES(fc_med.los_days, 2)[OFFSET(1)]
     FROM FinalCohortMetrics AS fc_med
     WHERE fc_med.readmitted_30_day = FALSE) AS median_los_non_readmitted_days,
    -- Percentage of index stays with LOS > 6 days
    SAFE_DIVIDE(SUM(CASE WHEN fc.los_days > 6 THEN 1 ELSE 0 END), COUNT(fc.hadm_id)) * 100 AS percent_index_stays_gt_6_days
FROM
    FinalCohortMetrics AS fc;