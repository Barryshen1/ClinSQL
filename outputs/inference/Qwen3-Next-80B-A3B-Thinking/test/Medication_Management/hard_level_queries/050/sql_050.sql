WITH aki_patients AS (
    SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 81 AND 91
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          WHERE d.hadm_id = a.hadm_id
            AND d.icd_code LIKE 'N17%'
      )
),

cns_drugs AS (
    SELECT hadm_id, MAX(CASE WHEN LOWER(drug) IN (
        'morphine', 'fentanyl', 'midazolam', 'lorazepam', 'diazepam', 'propofol', 'haloperidol', 
        'alprazolam', 'clonazepam', 'zolpidem', 'buprenorphine', 'methadone', 'oxycodone', 
        'hydrocodone', 'codeine', 'tramadol', 'butorphanol', 'pentazocine', 'nalbuphine', 'levorphanol'
    ) THEN 1 ELSE 0 END) AS has_cns
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    GROUP BY hadm_id
),

nephro_drugs AS (
    SELECT hadm_id, MAX(CASE WHEN LOWER(drug) IN (
        'gentamicin', 'vancomycin', 'amphotericin b', 'cisplatin', 'ibuprofen', 'naproxen', 
        'diclofenac', 'ketorolac', 'contrast', 'iodinated contrast', 'radiocontrast', 
        'cyclosporine', 'tacrolimus', 'tobramycin', 'amikacin', 'neomycin', 'polymyxin b', 'colistin'
    ) THEN 1 ELSE 0 END) AS has_nephro
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    GROUP BY hadm_id
),

drug_counts AS (
    SELECT hadm_id, COUNT(DISTINCT drug) AS complexity_score
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    GROUP BY hadm_id
),

grouped AS (
    SELECT 
        a.hadm_id,
        a.hospital_expire_flag,
        a.admittime,
        a.dischtime,
        dc.complexity_score,
        CASE 
            WHEN (c.has_cns = 1 AND n.has_nephro = 1) THEN 'both'
            ELSE 'other'
        END AS group_flag
    FROM aki_patients a
    LEFT JOIN cns_drugs c ON a.hadm_id = c.hadm_id
    LEFT JOIN nephro_drugs n ON a.hadm_id = n.hadm_id
    LEFT JOIN drug_counts dc ON a.hadm_id = dc.hadm_id
),

complexity_quartiles AS (
    SELECT 
        group_flag,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY complexity_score) AS q25,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY complexity_score) AS q50,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY complexity_score) AS q75,
        AVG(complexity_score) AS mean_complexity
    FROM grouped
    GROUP BY group_flag
),

overall_stats AS (
    SELECT 
        group_flag,
        AVG(TIMESTAMP_DIFF(dischtime, admittime, 'DAY')) AS avg_los_overall,
        AVG(hospital_expire_flag) AS mortality_overall
    FROM grouped
    GROUP BY group_flag
),

top_quartile AS (
    SELECT 
        group_flag,
        AVG(TIMESTAMP_DIFF(dischtime, admittime, 'DAY')) AS avg_los_top,
        AVG(hospital_expire_flag) AS mortality_top
    FROM (
        SELECT 
            group_flag,
            dischtime,
            admittime,
            hospital_expire_flag,
            NTILE(4) OVER (PARTITION BY group_flag ORDER BY complexity_score) AS quartile
        FROM grouped
    ) AS quartiles
    WHERE quartile = 4
    GROUP BY group_flag
)

SELECT 
    c.group_flag,
    c.q25,
    c.q50,
    c.q75,
    c.mean_complexity,
    o.avg_los_overall,
    o.mortality_overall,
    t.avg_los_top,
    t.mortality_top
FROM complexity_quartiles c
JOIN overall_stats o ON c.group_flag = o.group_flag
JOIN top_quartile t ON c.group_flag = t.group_flag;