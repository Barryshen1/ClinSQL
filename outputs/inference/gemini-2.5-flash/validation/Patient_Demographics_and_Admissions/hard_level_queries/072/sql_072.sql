WITH admissions_with_next_event AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.admission_location,
        ad.insurance,
        ad.hospital_expire_flag,
        -- Get the admittime of the next admission for the same patient
        LEAD(ad.admittime) OVER (PARTITION BY ad.subject_id ORDER BY ad.admittime) AS next_admittime,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
),
cohort_index_admissions AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.los_days,
        -- Calculate age at admission
        (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission,
        -- Determine 30-day readmission status
        CASE
            WHEN a.next_admittime IS NOT NULL
            AND DATE_DIFF(a.next_admittime, a.dischtime, DAY) <= 30
            THEN TRUE
            ELSE FALSE
        END AS readmitted_30d
    FROM
        admissions_with_next_event a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id AND a.subject_id = di.subject_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
        AND a.admission_location = 'SKILLED NURSING FACILITY'
        AND a.insurance = 'Medicare'
        AND di.seq_num = 1 -- Principal diagnosis
        AND di.icd_code IN (
            -- ICD-9 codes for Acute Respiratory Failure
            '51881', '51883', '51884',
            -- ICD-10 codes for Acute Respiratory Failure
            'J9600', 'J9601', 'J9602', 'J9620', 'J9621', 'J9622'
        )
)
SELECT
    COUNT(hadm_id) AS total_index_admissions,
    SUM(CASE WHEN readmitted_30d THEN 1 ELSE 0 END) AS readmitted_count,
    SAFE_DIVIDE(SUM(CASE WHEN readmitted_30d THEN 1 ELSE 0 END), COUNT(hadm_id)) AS readmission_rate_30d,
    -- Calculate median LOS for readmitted patients
    APPROX_QUANTILES(CASE WHEN readmitted_30d THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_los_readmitted,
    -- Calculate median LOS for non-readmitted patients
    APPROX_QUANTILES(CASE WHEN NOT readmitted_30d THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_los_not_readmitted,
    SUM(CASE WHEN los_days > 8 THEN 1 ELSE 0 END) AS los_gt_8_days_count,
    SAFE_DIVIDE(SUM(CASE WHEN los_days > 8 THEN 1 ELSE 0 END), COUNT(hadm_id)) AS percent_los_gt_8_days
FROM
    cohort_index_admissions;