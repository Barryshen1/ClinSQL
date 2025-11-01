WITH base_cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id, 
        a.admittime, 
        a.dischtime, 
        a.hospital_expire_flag,
        CASE 
            WHEN d.hadm_id IS NOT NULL THEN 1 
            ELSE 0 
        END AS hemorrhagic_stroke
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    LEFT JOIN (
        SELECT DISTINCT hadm_id 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
        WHERE icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'
    ) d
        ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'F' 
        AND p.anchor_age BETWEEN 48 AND 58
),

meds_in_48h AS (
    SELECT 
        bc.hadm_id,
        COUNT(DISTINCT pr.drug) AS total_meds,
        COUNT(DISTINCT CASE 
            WHEN LOWER(pr.drug) LIKE '%citalopram%' OR
                 LOWER(pr.drug) LIKE '%escitalopram%' OR
                 LOWER(pr.drug) LIKE '%fluoxetine%' OR
                 LOWER(pr.drug) LIKE '%sertraline%' OR
                 LOWER(pr.drug) LIKE '%paroxetine%' OR
                 LOWER(pr.drug) LIKE '%fluvoxamine%' OR
                 LOWER(pr.drug) LIKE '%venlafaxine%' OR
                 LOWER(pr.drug) LIKE '%duloxetine%' OR
                 LOWER(pr.drug) LIKE '%trazodone%' OR
                 LOWER(pr.drug) LIKE '%sumatriptan%' OR
                 LOWER(pr.drug) LIKE '%almotriptan%' OR
                 LOWER(pr.drug) LIKE '%eletriptan%' OR
                 LOWER(pr.drug) LIKE '%frovatriptan%' OR
                 LOWER(pr.drug) LIKE '%naratriptan%' OR
                 LOWER(pr.drug) LIKE '%rizatriptan%' OR
                 LOWER(pr.drug) LIKE '%zolmitriptan%' 
            THEN pr.drug 
        END) AS serotonergic_meds
    FROM base_cohort bc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON bc.hadm_id = pr.hadm_id
    WHERE pr.starttime BETWEEN bc.admittime AND DATETIME_ADD(bc.admittime, INTERVAL 48 HOUR)
    GROUP BY bc.hadm_id
),

with_meds AS (
    SELECT 
        bc.*,
        COALESCE(m.total_meds, 0) AS total_meds,
        COALESCE(m.serotonergic_meds, 0) AS serotonergic_meds,
        CASE 
            WHEN COALESCE(m.serotonergic_meds, 0) >= 2 THEN '>=2'
            ELSE '<2'
        END AS serotonergic_group,
        DATETIME_DIFF(bc.dischtime, bc.admittime, DAY) AS los_days
    FROM base_cohort bc
    LEFT JOIN meds_in_48h m
        ON bc.hadm_id = m.hadm_id
),

quartiles AS (
    SELECT 
        hadm_id,
        NTILE(4) OVER (ORDER BY total_meds) AS complexity_quartile
    FROM with_meds
)

SELECT 
    wm.hemorrhagic_stroke,
    wm.serotonergic_group,
    q.complexity_quartile,
    COUNT(*) AS num_patients,
    AVG(wm.los_days) AS avg_los,
    SUM(wm.hospital_expire_flag) AS mortality_count,
    AVG(CAST(wm.hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM with_meds wm
LEFT JOIN quartiles q
    ON wm.hadm_id = q.hadm_id
GROUP BY 
    wm.hemorrhagic_stroke,
    wm.serotonergic_group,
    q.complexity_quartile
ORDER BY 
    wm.hemorrhagic_stroke,
    wm.serotonergic_group,
    q.complexity_quartile;