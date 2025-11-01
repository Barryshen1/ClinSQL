WITH base_cohort AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        -- Calculate age at admission: using anchor_year and admittime
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 87 AND 97
),
acs_patients AS (
    SELECT 
        bc.subject_id,
        bc.hadm_id,
        bc.admittime,
        bc.dischtime,
        bc.hospital_expire_flag,
        bc.age_at_admission
    FROM base_cohort bc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON bc.subject_id = d.subject_id AND bc.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE dd.icd_code LIKE 'I21%'  -- ICD-10 codes for ACS (Acute myocardial infarction)
        AND d.icd_version = 10  -- Ensure ICD-10
    GROUP BY bc.subject_id, bc.hadm_id, bc.admittime, bc.dischtime, bc.hospital_expire_flag, bc.age_at_admission
),
lab_instability AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        COUNT(lab.labevent_id) AS instability_score
    FROM acs_patients a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab 
        ON a.subject_id = lab.subject_id AND a.hadm_id = lab.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli 
        ON lab.itemid = dli.itemid
    WHERE lab.charttime BETWEEN a.admittime AND a.admittime + INTERVAL 72 HOUR
        AND dli.ref_range_lower IS NOT NULL
        AND dli.ref_range_upper IS NOT NULL
        AND lab.valuenum IS NOT NULL
        AND (lab.valuenum < dli.ref_range_lower OR lab.valuenum > dli.ref_range_upper)
    GROUP BY a.subject_id, a.hadm_id
),
p95 AS (
    SELECT 
        APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95_instability
    FROM lab_instability
),
high_instability AS (
    SELECT 
        li.subject_id,
        li.hadm_id,
        li.instability_score,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM lab_instability li
    INNER JOIN acs_patients a 
        ON li.subject_id = a.subject_id AND li.hadm_id = a.hadm_id
    CROSS JOIN p95
    WHERE li.instability_score >= p95.p95_instability
),
high_outcomes AS (
    SELECT 
        AVG(DATEDIFF(dischtime, admittime)) AS mean_los_high,
        AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_high,
        AVG(instability_score) AS avg_critical_events_high
    FROM high_instability
),
general_cohort AS (
    SELECT 
        bc.subject_id,
        bc.hadm_id,
        bc.admittime
    FROM base_cohort bc
),
general_lab_instability AS (
    SELECT 
        g.subject_id,
        g.hadm_id,
        COUNT(lab.labevent_id) AS instability_score
    FROM general_cohort g
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab 
        ON g.subject_id = lab.subject_id AND g.hadm_id = lab.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli 
        ON lab.itemid = dli.itemid
    WHERE lab.charttime BETWEEN g.admittime AND g.admittime + INTERVAL 72 HOUR
        AND dli.ref_range_lower IS NOT NULL
        AND dli.ref_range_upper IS NOT NULL
        AND lab.valuenum IS NOT NULL
        AND (lab.valuenum < dli.ref_range_lower OR lab.valuenum > dli.ref_range_upper)
    GROUP BY g.subject_id, g.hadm_id
),
general_avg AS (
    SELECT 
        AVG(instability_score) AS avg_critical_events_general
    FROM general_lab_instability
)
SELECT 
    p95.p95_instability AS p95_instability_score,
    ho.mean_los_high,
    ho.mortality_high,
    ho.avg_critical_events_high,
    ga.avg_critical_events_general
FROM p95
CROSS JOIN high_outcomes ho
CROSS JOIN general_avg ga;