WITH filtered_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        l.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id AND d.seq_num = 1
    JOIN (
        SELECT 
            hadm_id,
            valuenum,
            charttime,
            ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
        FROM `physionet-data.mimiciv_3_1_hosp.labevents`
        WHERE itemid = 50911
        AND valuenum IS NOT NULL
    ) l ON a.hadm_id = l.hadm_id AND l.rn = 1 AND l.charttime >= a.admittime
    WHERE 
        p.gender = 'M'
        AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 50 AND 60
        AND (
            (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code IN ('786.50', '786.59'))) OR
            (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'R07%'))
        )
        AND l.valuenum > 0.014
)
SELECT 
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(hadm_id) AS admission_count,
    AVG(valuenum) AS mean,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) AS median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS iqr
FROM filtered_admissions;