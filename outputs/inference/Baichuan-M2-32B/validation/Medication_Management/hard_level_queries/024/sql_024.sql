WITH multi_trauma_patients AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 68 AND 78
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = a.hadm_id
                AND d.icd_code BETWEEN 'S00' AND 'T98'
            GROUP BY d.hadm_id
            HAVING COUNT(DISTINCT d.icd_code) >= 2
        )
),
first_24h_prescriptions AS (
    SELECT 
        p.hadm_id,
        COUNT(DISTINCT p.drug) AS distinct_drug_count
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN multi_trauma_patients m
        ON p.hadm_id = m.hadm_id
    WHERE p.starttime BETWEEN m.admittime AND TIMESTAMP_ADD(m.admittime, INTERVAL 24 HOUR)
    GROUP BY p.hadm_id
),
serotonergic_drugs AS (
    SELECT drug_name
    FROM UNNEST([
        'sertraline', 'citalopram', 'fluoxetine', 'paroxetine', 'fluvoxamine', 
        'venlafaxine', 'duloxetine', 'trazodone', 'bupropion', 'mirtazapine', 
        'desvenlafaxine', 'vortioxetine', 'escitalopram', 'isocarboxazid', 
        'phenelzine', 'selegiline', 'tranylcypromine', 'carbamazepine', 
        'valproate', 'lamotrigine', 'topiramate', 'oxcarbazepine', 
        'gabapentin', 'pregabalin', 'milnacipran', 'buspirone'
    ]) AS drug_name
),
serotonergic_risk AS (
    SELECT 
        p.hadm_id,
        COUNT(DISTINCT p.drug) AS sero_drug_count
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN multi_trauma_patients m
        ON p.hadm_id = m.hadm_id
    INNER JOIN serotonergic_drugs s
        ON p.drug = s.drug_name
    WHERE p.starttime BETWEEN m.admittime AND TIMESTAMP_ADD(m.admittime, INTERVAL 24 HOUR)
    GROUP BY p.hadm_id
    HAVING sero_drug_count >= 2
),
multi_trauma_with_complexity AS (
    SELECT 
        m.hadm_id,
        m.subject_id,
        m.admittime,
        m.dischtime,
        m.hospital_expire_flag,
        COALESCE(f.distinct_drug_count, 0) AS medication_complexity,
        CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_sero_risk
    FROM multi_trauma_patients m
    LEFT JOIN first_24h_prescriptions f
        ON m.hadm_id = f.hadm_id
    LEFT JOIN serotonergic_risk s
        ON m.hadm_id = s.hadm_id
),
percentiles AS (
    SELECT 
        hadm_id,
        medication_complexity,
        PERCENT_RANK() OVER (ORDER BY medication_complexity) AS percentile_rank
    FROM multi_trauma_with_complexity
),
group_summary AS (
    SELECT 
        CASE has_sero_risk 
            WHEN 1 THEN 'with_risk' 
            WHEN 0 THEN 'without_risk' 
        END AS group_type,
        APPROX_QUANTILES(medication_complexity, 100)[SAFE_OFFSET(25)] AS quartile_25,
        APPROX_QUANTILES(medication_complexity, 100)[SAFE_OFFSET(50)] AS quartile_50,
        APPROX_QUANTILES(medication_complexity, 100)[SAFE_OFFSET(75)] AS quartile_75,
        AVG(medication_complexity) AS average_complexity,
        AVG(percentile_rank) AS average_percentile_rank,
        AVG(DATEDIFF(CAST(m.dischtime AS DATE), CAST(m.admittime AS DATE))) AS avg_los,
        AVG(CAST(m.hospital_expire_flag AS FLOAT64)) AS mortality_rate
    FROM multi_trauma_with_complexity m
    JOIN percentiles p
        ON m.hadm_id = p.hadm_id
    GROUP BY has_sero_risk
),
top_quartile AS (
    SELECT 
        hadm_id,
        medication_complexity,
        DATEDIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE)) AS los,
        hospital_expire_flag
    FROM (
        SELECT 
            *,
            NTILE(4) OVER (ORDER BY medication_complexity DESC) AS quartile
        FROM multi_trauma_with_complexity
    ) 
    WHERE quartile = 1
),
top_quartile_summary AS (
    SELECT 
        AVG(los) AS avg_los,
        AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
    FROM top_quartile
)

-- Group comparison results
SELECT 
    'group_comparison' AS result_type,
    group_type,
    quartile_25,
    quartile_50,
    quartile_75,
    average_complexity,
    average_percentile_rank,
    avg_los,
    mortality_rate
FROM group_summary

UNION ALL

-- Top quartile results
SELECT 
    'top_quartile' AS result_type,
    'top_quartile' AS group_type,
    NULL AS quartile_25,
    NULL AS quartile_50,
    NULL AS quartile_75,
    NULL AS average_complexity,
    NULL AS average_percentile_rank,
    avg_los,
    mortality_rate
FROM top_quartile_summary;