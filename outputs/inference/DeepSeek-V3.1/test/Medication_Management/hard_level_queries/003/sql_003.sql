WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_hospital,
        pt.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON adm.subject_id = pt.subject_id
    WHERE pt.gender = 'M'
        AND pt.anchor_age BETWEEN 39 AND 49
),

meds AS (
    SELECT 
        p.subject_id,
        p.hadm_id,
        p.drug,
        p.starttime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN cohort c
        ON p.hadm_id = c.hadm_id
    WHERE p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
),

-- Flag QT and bleeding drugs
drug_flags AS (
    SELECT 
        subject_id,
        hadm_id,
        MAX(CASE WHEN LOWER(drug) LIKE '%amiodarone%' OR LOWER(drug) LIKE '%sotalol%' OR LOWER(drug) LIKE '%haloperidol%' OR LOWER(drug) LIKE '%quinidine%' OR LOWER(drug) LIKE '%disopyramide%' OR LOWER(drug) LIKE '%dofetilide%' OR LOWER(drug) LIKE '%ibutilide%' OR LOWER(drug) LIKE '%procainamide%' OR LOWER(drug) LIKE '%erythromycin%' OR LOWER(drug) LIKE '%clarithromycin%' OR LOWER(drug) LIKE '%chlorpromazine%' OR LOWER(drug) LIKE '%thioridazine%' OR LOWER(drug) LIKE '%mesoridazine%' OR LOWER(drug) LIKE '%pimozide%' OR LOWER(drug) LIKE '%ziprasidone%' OR LOWER(drug) LIKE '%arsenic trioxide%' OR LOWER(drug) LIKE '%levomethadyl%' OR LOWER(drug) LIKE '%pentamidine%' OR LOWER(drug) LIKE '%tacrolimus%' OR LOWER(drug) LIKE '%vandetanib%' OR LOWER(drug) LIKE '%citalopram%' OR LOWER(drug) LIKE '%escitalopram%' THEN 1 ELSE 0 END) AS has_qt_drug,
        MAX(CASE WHEN LOWER(drug) LIKE '%warfarin%' OR LOWER(drug) LIKE '%heparin%' OR LOWER(drug) LIKE '%enoxaparin%' OR LOWER(drug) LIKE '%clopidogrel%' OR LOWER(drug) LIKE '%prasugrel%' OR LOWER(drug) LIKE '%ticagrelor%' OR LOWER(drug) LIKE '%dabigatran%' OR LOWER(drug) LIKE '%rivaroxaban%' OR LOWER(drug) LIKE '%apixaban%' OR LOWER(drug) LIKE '%edoxaban%' OR LOWER(drug) LIKE '%aspirin%' THEN 1 ELSE 0 END) AS has_bleeding_drug
    FROM meds
    GROUP BY subject_id, hadm_id
),

-- Compute complexity (number of distinct drugs) per admission
complexity AS (
    SELECT 
        m.hadm_id,
        COUNT(DISTINCT drug) AS med_complexity
    FROM meds m
    GROUP BY m.hadm_id
),

-- Combine with cohort and flags
cohort_with_flags AS (
    SELECT 
        c.*,
        COALESCE(df.has_qt_drug, 0) AS has_qt_drug,
        COALESCE(df.has_bleeding_drug, 0) AS has_bleeding_drug,
        COALESCE(cmp.med_complexity, 0) AS med_complexity
    FROM cohort c
    LEFT JOIN drug_flags df
        ON c.hadm_id = df.hadm_id
    LEFT JOIN complexity cmp
        ON c.hadm_id = cmp.hadm_id
),

-- Define groups (renamed from 'groups' to avoid reserved keyword)
group_categories AS (
    SELECT 
        *,
        CASE 
            WHEN has_qt_drug = 1 THEN 'QT_prolonging'
            WHEN has_bleeding_drug = 1 THEN 'Bleeding_risk'
            ELSE 'General'
        END AS group_category
    FROM cohort_with_flags
),

-- Compute percentile rank within each group
with_percentile AS (
    SELECT 
        *,
        PERCENT_RANK() OVER (PARTITION BY group_category ORDER BY med_complexity) AS complexity_percentile
    FROM group_categories
)

-- For each group, report:
--   group category
--   number of patients
--   average medication complexity
--   average LOS
--   mortality rate
-- And for the top quartile (complexity >= 75th percentile) in each group, report:
--   average LOS and mortality

SELECT 
    group_category,
    COUNT(*) AS n_patients,
    AVG(med_complexity) AS avg_complexity,
    AVG(los_hospital) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    -- For top quartile:
    (SELECT AVG(los_hospital) 
     FROM with_percentile wp2 
     WHERE wp2.group_category = wp1.group_category 
        AND complexity_percentile >= 0.75) AS avg_los_top25,
    (SELECT AVG(hospital_expire_flag) 
     FROM with_percentile wp2 
     WHERE wp2.group_category = wp1.group_category 
        AND complexity_percentile >= 0.75) AS mortality_top25
FROM with_percentile wp1
GROUP BY group_category
ORDER BY group_category;