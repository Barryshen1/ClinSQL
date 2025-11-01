WITH ich_admissions AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age,
        p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
    WHERE 
        p.gender = 'F'
        AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 87 AND 97
        AND d.icd_code IN ('I60', 'I61', 'I62') -- ICD-10 codes for ICH
),
med_complexity AS (
    SELECT 
        i.hadm_id,
        COUNT(DISTINCT pr.drug) AS unique_drugs,
        COUNT(DISTINCT pr.route) AS unique_routes,
        COUNT(DISTINCT pr.drug) + COUNT(DISTINCT pr.route) AS complexity_score
    FROM ich_admissions i
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
        ON i.hadm_id = pr.hadm_id
        AND pr.starttime BETWEEN i.admittime AND i.admittime + INTERVAL '48' HOUR
    GROUP BY i.hadm_id
),
readmissions AS (
    SELECT 
        a1.hadm_id,
        CASE WHEN EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2 
            WHERE a2.subject_id = a1.subject_id 
              AND a2.admittime > a1.dischtime 
              AND a2.admittime <= a1.dischtime + INTERVAL '30' DAY
        ) THEN 1 ELSE 0 END AS readmitted
    FROM ich_admissions a1
),
quartiles AS (
    SELECT 
        m.hadm_id,
        m.complexity_score,
        NTILE(4) OVER (ORDER BY m.complexity_score) AS quartile
    FROM med_complexity m
),
final_agg AS (
    SELECT 
        q.quartile,
        COUNT(*) AS admissions,
        MIN(q.complexity_score) AS min_score,
        MAX(q.complexity_score) AS max_score,
        AVG(DATE_DIFF(DATE(i.dischtime), DATE(i.admittime), DAY)) AS avg_los_days,
        AVG(SAFE_CAST(i.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
        AVG(SAFE_CAST(r.readmitted AS FLOAT64)) AS readmission_rate
    FROM quartiles q
    INNER JOIN ich_admissions i ON q.hadm_id = i.hadm_id
    INNER JOIN readmissions r ON q.hadm_id = r.hadm_id
    GROUP BY q.quartile
    ORDER BY q.quartile
)
SELECT 
    quartile,
    admissions,
    min_score,
    max_score,
    avg_los_days,
    mortality_rate,
    readmission_rate
FROM final_agg
ORDER BY quartile;