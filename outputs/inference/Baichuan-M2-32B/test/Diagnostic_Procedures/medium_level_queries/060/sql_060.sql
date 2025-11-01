WITH eligible_patients AS (
    SELECT
        p.subject_id,
        p.anchor_year,
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        EXTRACT(YEAR FROM a.admittime) AS admission_year,
        (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 49 AND 59
),
primary_hf_admissions AS (
    SELECT
        e.subject_id,
        e.hadm_id,
        e.admission_year,
        e.age_at_admission,
        e.admittime,
        e.dischtime
    FROM
        eligible_patients e
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON e.subject_id = d.subject_id AND e.hadm_id = d.hadm_id
    WHERE
        d.seq_num = 1
        AND (d.icd_code LIKE 'I50%' OR d.icd_code LIKE '428%')
),
admissions_with_los AS (
    SELECT
        subject_id,
        hadm_id,
        admission_year,
        age_at_admission,
        admittime,
        dischtime,
        TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
    FROM
        primary_hf_admissions
    WHERE
        TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 7
),
icu_flag AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.los_days,
        CASE WHEN i.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS icu_use
    FROM
        admissions_with_los a
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
),
ct_mri_counts AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        COUNT(DISTINCT c.hcpcs_cd) AS ct_mri_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.hcpcsevents` c
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
        ON c.hcpcs_cd = d.code
    WHERE
        d.short_description LIKE '%CT%' OR d.short_description LIKE '%MRI%'
    GROUP BY
        c.subject_id, c.hadm_id
),
final_data AS (
    SELECT
        i.subject_id,
        i.hadm_id,
        i.los_days,
        i.icu_use,
        COALESCE(c.ct_mri_count, 0) AS ct_mri_count
    FROM
        icu_flag i
    LEFT JOIN
        ct_mri_counts c
        ON i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id
)
SELECT
    icu_use,
    CASE
        WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    COUNT(DISTINCT hadm_id) AS admission_count,
    AVG(ct_mri_count) AS mean_ct_mri_per_admission
FROM
    final_data
GROUP BY
    icu_use, los_group
HAVING
    los_group IS NOT NULL
ORDER BY
    icu_use, los_group;