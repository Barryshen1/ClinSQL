WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.anchor_age,
        i.hadm_id, 
        i.stay_id,
        i.intime,
        i.outtime,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        -- Calculate hospital LOS in days
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON i.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON i.hadm_id = d.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 84 AND 94
        AND (
            (d.icd_version = 9 AND d.icd_code LIKE '250.1%') OR
            (d.icd_version = 10 AND d.icd_code LIKE 'E1%.1%')
        )
    -- Get first ICU stay per admission
    QUALIFY ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) = 1
),

-- Get all prescriptions within first 48h of ICU stay
prescriptions_48h AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        c.intime,
        pr.drug,
        pr.starttime
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON c.hadm_id = pr.hadm_id
    WHERE pr.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),

-- Flag hyperkalemia-risk drugs (common examples)
hyperkalemia_drugs AS (
    SELECT 
        subject_id,
        hadm_id,
        stay_id,
        MAX(CASE 
            WHEN REGEXP_CONTAINS(LOWER(drug), r'(lisinopril|enalapril|ramipril|captopril|quinapril|perindopril|trandolapril|benazepril|moexipril|fosinopril)') THEN 1
            WHEN REGEXP_CONTAINS(LOWER(drug), r'(losartan|valsartan|irbesartan|candesartan|telmisartan|olmesartan|azilsartan|eprosartan)') THEN 1
            WHEN REGEXP_CONTAINS(LOWER(drug), r'(spironolactone|eplerenone|amiloride|triamterene)') THEN 1
            WHEN REGEXP_CONTAINS(LOWER(drug), r'(ibuprofen|naproxen|diclofenac|celecoxib|indomethacin|meloxicam|ketorolac|aspirin)') THEN 1
            WHEN REGEXP_CONTAINS(LOWER(drug), r'(heparin|low molecular weight heparin|dalteparin|enoxaparin)') THEN 1
            WHEN REGEXP_CONTAINS(LOWER(drug), r'(trimethoprim|sulfamethoxazole') THEN 1
            ELSE 0 
        END) AS has_hyperkalemia_drug
    FROM prescriptions_48h
    GROUP BY subject_id, hadm_id, stay_id
),

-- Count distinct drugs for medication complexity
medication_complexity AS (
    SELECT 
        p.subject_id,
        p.hadm_id,
        p.stay_id,
        COUNT(DISTINCT drug) AS num_drugs
    FROM prescriptions_48h p
    GROUP BY subject_id, hadm_id, stay_id
),

-- Combine all information
cohort_with_flags AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        c.anchor_age,
        c.admittime,
        c.dischtime,
        c.hosp_los,
        c.hospital_expire_flag,
        COALESCE(h.has_hyperkalemia_drug, 0) AS has_hyperkalemia_drug,
        COALESCE(m.num_drugs, 0) AS num_drugs
    FROM cohort c
    LEFT JOIN hyperkalemia_drugs h
        ON c.stay_id = h.stay_id
    LEFT JOIN medication_complexity m
        ON c.stay_id = m.stay_id
),

-- Assign complexity quartile for the entire cohort
cohort_with_quartile AS (
    SELECT *,
        NTILE(4) OVER (ORDER BY num_drugs) AS complexity_quartile
    FROM cohort_with_flags
)

-- Main analysis
SELECT 
    has_hyperkalemia_drug,
    COUNT(*) AS n_patients,
    AVG(num_drugs) AS mean_medication_complexity,
    -- For percentile: we already have quartile, so we can report the distribution?
    -- Instead, we'll report the median and IQR? But question says "percentile", so we'll compute quartiles.
    -- Actually, we'll compute the quartiles for the entire cohort and then group by hyperkalemia flag.
    -- So we compute the quartiles for each group? But the question says "compare those with vs without", so we need to compute the quartiles for the entire cohort and then see the distribution in each group?
    -- Alternatively, we can compute the median and IQR per group.
    APPROX_QUANTILES(num_drugs, 4) AS quartiles,  -- This returns an array [min, q1, median, q3, max]
    AVG(hosp_los) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate
FROM cohort_with_quartile
GROUP BY has_hyperkalemia_drug

UNION ALL

-- For top complexity quartile
SELECT 
    2 AS has_hyperkalemia_drug,  -- Use 2 to indicate top quartile group
    COUNT(*) AS n_patients,
    NULL AS mean_medication_complexity,
    NULL AS quartiles,
    AVG(hosp_los) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate
FROM cohort_with_quartile
WHERE complexity_quartile = 4
ORDER BY has_hyperkalemia_drug;