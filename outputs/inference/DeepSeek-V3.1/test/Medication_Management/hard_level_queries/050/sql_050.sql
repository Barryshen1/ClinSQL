WITH cohort AS (
    -- Female patients aged 81-91 with AKI
    SELECT 
        adm.subject_id, 
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR)/24.0 AS los_days,
        pat.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE pat.gender = 'F'
        AND pat.anchor_age BETWEEN 81 AND 91
        AND (
            (diag.icd_version = 9 AND diag.icd_code LIKE '584%') OR
            (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')
        )
),

-- CNS depressant drugs: benzodiazepines, opioids, antipsychotics, sedatives
cns_drugs AS (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE LOWER(drug) LIKE '%diazepam%' OR
          LOWER(drug) LIKE '%lorazepam%' OR
          LOWER(drug) LIKE '%midazolam%' OR
          LOWER(drug) LIKE '%oxycodone%' OR
          LOWER(drug) LIKE '%morphine%' OR
          LOWER(drug) LIKE '%fentanyl%' OR
          LOWER(drug) LIKE '%haloperidol%' OR
          LOWER(drug) LIKE '%quetiapine%' OR
          LOWER(drug) LIKE '%propofol%' OR
          LOWER(drug) LIKE '%dexmedetomidine%'
),

-- Nephrotoxic drugs: NSAIDs, aminoglycosides, vancomycin, ACE inhibitors, etc.
nephro_drugs AS (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE LOWER(drug) LIKE '%ibuprofen%' OR
          LOWER(drug) LIKE '%naproxen%' OR
          LOWER(drug) LIKE '%ketorolac%' OR
          LOWER(drug) LIKE '%gentamicin%' OR
          LOWER(drug) LIKE '%tobramycin%' OR
          LOWER(drug) LIKE '%vancomycin%' OR
          LOWER(drug) LIKE '%lisinopril%' OR
          LOWER(drug) LIKE '%enalapril%' OR
          LOWER(drug) LIKE '%furosemide%' OR
          LOWER(drug) LIKE '%contrast%'
),

-- Medication complexity: count distinct drugs per admission
med_complexity AS (
    SELECT 
        subject_id, 
        hadm_id, 
        COUNT(DISTINCT drug) AS num_drugs
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    GROUP BY subject_id, hadm_id
),

-- Combine cohort with exposure flags and complexity
cohort_with_flags AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        c.los_days,
        c.hospital_expire_flag,
        mc.num_drugs,
        CASE WHEN cns.subject_id IS NOT NULL AND neph.subject_id IS NOT NULL 
             THEN 1 ELSE 0 END AS has_both_drugs
    FROM cohort c
    LEFT JOIN cns_drugs cns 
        ON c.subject_id = cns.subject_id AND c.hadm_id = cns.hadm_id
    LEFT JOIN nephro_drugs neph 
        ON c.subject_id = neph.subject_id AND c.hadm_id = neph.hadm_id
    LEFT JOIN med_complexity mc 
        ON c.subject_id = mc.subject_id AND c.hadm_id = mc.hadm_id
)

-- Calculate statistics by group
SELECT 
    has_both_drugs,
    COUNT(*) AS n_patients,
    -- Medication complexity quartiles and mean
    APPROX_QUANTILES(num_drugs, 4)[OFFSET(1)] AS q1_complexity,
    APPROX_QUANTILES(num_drugs, 4)[OFFSET(2)] AS median_complexity,
    APPROX_QUANTILES(num_drugs, 4)[OFFSET(3)] AS q3_complexity,
    AVG(num_drugs) AS mean_complexity,
    -- Overall LOS and mortality
    AVG(los_days) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    -- Top-quartile complexity group: mortality and LOS
    AVG(CASE WHEN num_drugs >= (SELECT APPROX_QUANTILES(num_drugs, 4)[OFFSET(3)] 
                                FROM cohort_with_flags) 
             THEN hospital_expire_flag ELSE NULL END) AS top_quartile_mortality,
    AVG(CASE WHEN num_drugs >= (SELECT APPROX_QUANTILES(num_drugs, 4)[OFFSET(3)] 
                                FROM cohort_with_flags) 
             THEN los_days ELSE NULL END) AS top_quartile_mean_los
FROM cohort_with_flags
GROUP BY has_both_drugs;