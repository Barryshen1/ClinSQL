WITH serotonergic_drugs AS (
  SELECT 'sertraline' AS drug UNION ALL
  SELECT 'fluoxetine' UNION ALL
  SELECT 'paroxetine' UNION ALL
  SELECT 'citalopram' UNION ALL
  SELECT 'escitalopram' UNION ALL
  SELECT 'venlafaxine' UNION ALL
  SELECT 'duloxetine' UNION ALL
  SELECT 'sumatriptan' UNION ALL
  SELECT 'ondansetron' UNION ALL
  SELECT 'tramadol' UNION ALL
  SELECT 'trazodone' UNION ALL
  SELECT 'pethidine' UNION ALL
  SELECT 'methadone' UNION ALL
  SELECT 'dextromethorphan' UNION ALL
  SELECT 'fentanyl' UNION ALL
  SELECT 'morphine' UNION ALL
  SELECT 'hydromorphone' UNION ALL
  SELECT 'meperidine' UNION ALL
  SELECT 'codeine' UNION ALL
  SELECT 'buprenorphine' UNION ALL
  SELECT 'naltrexone' UNION ALL
  SELECT 'alprazolam' UNION ALL
  SELECT 'clonazepam' UNION ALL
  SELECT 'diazepam' UNION ALL
  SELECT 'lorazepam' UNION ALL
  SELECT 'midazolam' UNION ALL
  SELECT 'phenobarbital' UNION ALL
  SELECT 'phenytoin' UNION ALL
  SELECT 'carbamazepine' UNION ALL
  SELECT 'valproic acid' UNION ALL
  SELECT 'lamotrigine' UNION ALL
  SELECT 'topiramate' UNION ALL
  SELECT 'gabapentin' UNION ALL
  SELECT 'pregabalin' UNION ALL
  SELECT 'amitriptyline' UNION ALL
  SELECT 'nortriptyline' UNION ALL
  SELECT 'imipramine' UNION ALL
  SELECT 'clomipramine' UNION ALL
  SELECT 'protriptyline' UNION ALL
  SELECT 'doxepin' UNION ALL
  SELECT 'trimipramine' UNION ALL
  SELECT 'mirtazapine' UNION ALL
  SELECT 'bupropion' UNION ALL
  SELECT 'mianserin' UNION ALL
  SELECT 'nefazodone' UNION ALL
  SELECT 'vortioxetine' UNION ALL
  SELECT 'vilazodone' UNION ALL
  SELECT 'agomelatine' UNION ALL
  SELECT 'buspirone' UNION ALL
  SELECT 'tianeptine' UNION ALL
  SELECT 'moclobemide' UNION ALL
  SELECT 'selegiline' UNION ALL
  SELECT 'rasagiline' UNION ALL
  SELECT 'phenelzine' UNION ALL
  SELECT 'tranylcypromine' UNION ALL
  SELECT 'isocarboxazid' UNION ALL
  SELECT 'linezolid' UNION ALL
  SELECT 'methylene blue' UNION ALL
  SELECT 'granisetron' UNION ALL
  SELECT 'palonosetron' UNION ALL
  SELECT 'tropisetron' UNION ALL
  SELECT 'zolmitriptan' UNION ALL
  SELECT 'naratriptan' UNION ALL
  SELECT 'rizatriptan' UNION ALL
  SELECT 'almotriptan' UNION ALL
  SELECT 'frovatriptan' UNION ALL
  SELECT 'eletriptan' UNION ALL
  SELECT 'methysergide' UNION ALL
  SELECT 'ergotamine' UNION ALL
  SELECT 'dihydroergotamine'
),
cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    p.dod,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age AS age_at_admission,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE a.hadm_id = d.hadm_id
        AND d.icd_version = 10
        AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
    ) THEN 1 ELSE 0 END AS is_hemorrhagic_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age BETWEEN 48 AND 58
),
cohort_with_serotonergic AS (
  SELECT 
    c.*,
    (SELECT COUNT(DISTINCT p.drug)
     FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
     WHERE p.hadm_id = c.hadm_id
       AND p.starttime >= c.admittime
       AND p.starttime <= c.admittime + INTERVAL 48 HOUR
       AND LOWER(p.drug) IN (SELECT LOWER(drug) FROM serotonergic_drugs)
    ) AS num_serotonergic_drugs
  FROM cohort c
)
SELECT 
  is_hemorrhagic_stroke,
  num_serotonergic_drugs,
  COUNT(*) AS patient_count
FROM cohort_with_serotonergic
GROUP BY is_hemorrhagic_stroke, num_serotonergic_drugs
ORDER BY is_hemorrhagic_stroke, num_serotonergic_drugs;

-- Part 2: Outcomes for ≥2 vs <2 serotonergic drugs
WITH serotonergic_drugs AS (
  SELECT 'sertraline' AS drug UNION ALL
  SELECT 'fluoxetine' UNION ALL
  SELECT 'paroxetine' UNION ALL
  SELECT 'citalopram' UNION ALL
  SELECT 'escitalopram' UNION ALL
  SELECT 'venlafaxine' UNION ALL
  SELECT 'duloxetine' UNION ALL
  SELECT 'sumatriptan' UNION ALL
  SELECT 'ondansetron' UNION ALL
  SELECT 'tramadol' UNION ALL
  SELECT 'trazodone' UNION ALL
  SELECT 'pethidine' UNION ALL
  SELECT 'methadone' UNION ALL
  SELECT 'dextromethorphan' UNION ALL
  SELECT 'fentanyl' UNION ALL
  SELECT 'morphine' UNION ALL
  SELECT 'hydromorphone' UNION ALL
  SELECT 'meperidine' UNION ALL
  SELECT 'codeine' UNION ALL
  SELECT 'buprenorphine' UNION ALL
  SELECT 'naltrexone' UNION ALL
  SELECT 'alprazolam' UNION ALL
  SELECT 'clonazepam' UNION ALL
  SELECT 'diazepam' UNION ALL
  SELECT 'lorazepam' UNION ALL
  SELECT 'midazolam' UNION ALL
  SELECT 'phenobarbital' UNION ALL
  SELECT 'phenytoin' UNION ALL
  SELECT 'carbamazepine' UNION ALL
  SELECT 'valproic acid' UNION ALL
  SELECT 'lamotrigine' UNION ALL
  SELECT 'topiramate' UNION ALL
  SELECT 'gabapentin' UNION ALL
  SELECT 'pregabalin' UNION ALL
  SELECT 'amitriptyline' UNION ALL
  SELECT 'nortriptyline' UNION ALL
  SELECT 'imipramine' UNION ALL
  SELECT 'clomipramine' UNION ALL
  SELECT 'protriptyline' UNION ALL
  SELECT 'doxepin' UNION ALL
  SELECT 'trimipramine' UNION ALL
  SELECT 'mirtazapine' UNION ALL
  SELECT 'bupropion' UNION ALL
  SELECT 'mianserin' UNION ALL
  SELECT 'nefazodone' UNION ALL
  SELECT 'vortioxetine' UNION ALL
  SELECT 'vilazodone' UNION ALL
  SELECT 'agomelatine' UNION ALL
  SELECT 'buspirone' UNION ALL
  SELECT 'tianeptine' UNION ALL
  SELECT 'moclobemide' UNION ALL
  SELECT 'selegiline' UNION ALL
  SELECT 'rasagiline' UNION ALL
  SELECT 'phenelzine' UNION ALL
  SELECT 'tranylcypromine' UNION ALL
  SELECT 'isocarboxazid' UNION ALL
  SELECT 'linezolid' UNION ALL
  SELECT 'methylene blue' UNION ALL
  SELECT 'granisetron' UNION ALL
  SELECT 'palonosetron' UNION ALL
  SELECT 'tropisetron' UNION ALL
  SELECT 'zolmitriptan' UNION ALL
  SELECT 'naratriptan' UNION ALL
  SELECT 'rizatriptan' UNION ALL
  SELECT 'almotriptan' UNION ALL
  SELECT 'frovatriptan' UNION ALL
  SELECT 'eletriptan' UNION ALL
  SELECT 'methysergide' UNION ALL
  SELECT 'ergotamine' UNION ALL
  SELECT 'dihydroergotamine'
),
cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    p.dod,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age AS age_at_admission,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE a.hadm_id = d.hadm_id
        AND d.icd_version = 10
        AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
    ) THEN 1 ELSE 0 END AS is_hemorrhagic_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age BETWEEN 48 AND 58
),
cohort_with_serotonergic AS (
  SELECT 
    c.*,
    (SELECT COUNT(DISTINCT p.drug)
     FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
     WHERE p.hadm_id = c.hadm_id
       AND p.starttime >= c.admittime
       AND p.starttime <= c.admittime + INTERVAL 48 HOUR
       AND LOWER(p.drug) IN (SELECT LOWER(drug) FROM serotonergic_drugs)
    ) AS num_serotonergic_drugs
  FROM cohort c
),
cohort_with_outcomes AS (
  SELECT 
    *,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    hospital_expire_flag AS mortality
  FROM cohort_with_serotonergic
)
SELECT 
  CASE WHEN num_serotonergic_drugs >= 2 THEN '>=2' ELSE '<2' END AS serotonergic_group,
  AVG(los_days) AS avg_los,
  AVG(mortality) AS mortality_rate
FROM cohort_with_outcomes
GROUP BY serotonergic_group;

-- Part 3: Outcomes for top complexity quartile
WITH serotonergic_drugs AS (
  SELECT 'sertraline' AS drug UNION ALL
  SELECT 'fluoxetine' UNION ALL
  SELECT 'paroxetine' UNION ALL
  SELECT 'citalopram' UNION ALL
  SELECT 'escitalopram' UNION ALL
  SELECT 'venlafaxine' UNION ALL
  SELECT 'duloxetine' UNION ALL
  SELECT 'sumatriptan' UNION ALL
  SELECT 'ondansetron' UNION ALL
  SELECT 'tramadol' UNION ALL
  SELECT 'trazodone' UNION ALL
  SELECT 'pethidine' UNION ALL
  SELECT 'methadone' UNION ALL
  SELECT 'dextromethorphan' UNION ALL
  SELECT 'fentanyl' UNION ALL
  SELECT 'morphine' UNION ALL
  SELECT 'hydromorphone' UNION ALL
  SELECT 'meperidine' UNION ALL
  SELECT 'codeine' UNION ALL
  SELECT 'buprenorphine' UNION ALL
  SELECT 'naltrexone' UNION ALL
  SELECT 'alprazolam' UNION ALL
  SELECT 'clonazepam' UNION ALL
  SELECT 'diazepam' UNION ALL
  SELECT 'lorazepam' UNION ALL
  SELECT 'midazolam' UNION ALL
  SELECT 'phenobarbital' UNION ALL
  SELECT 'phenytoin' UNION ALL
  SELECT 'carbamazepine' UNION ALL
  SELECT 'valproic acid' UNION ALL
  SELECT 'lamotrigine' UNION ALL
  SELECT 'topiramate' UNION ALL
  SELECT 'gabapentin' UNION ALL
  SELECT 'pregabalin' UNION ALL
  SELECT 'amitriptyline' UNION ALL
  SELECT 'nortriptyline' UNION ALL
  SELECT 'imipramine' UNION ALL
  SELECT 'clomipramine' UNION ALL
  SELECT 'protriptyline' UNION ALL
  SELECT 'doxepin' UNION ALL
  SELECT 'trimipramine' UNION ALL
  SELECT 'mirtazapine' UNION ALL
  SELECT 'bupropion' UNION ALL
  SELECT 'mianserin' UNION ALL
  SELECT 'nefazodone' UNION ALL
  SELECT 'vortioxetine' UNION ALL
  SELECT 'vilazodone' UNION ALL
  SELECT 'agomelatine' UNION ALL
  SELECT 'buspirone' UNION ALL
  SELECT 'tianeptine' UNION ALL
  SELECT 'moclobemide' UNION ALL
  SELECT 'selegiline' UNION ALL
  SELECT 'rasagiline' UNION ALL
  SELECT 'phenelzine' UNION ALL
  SELECT 'tranylcypromine' UNION ALL
  SELECT 'isocarboxazid' UNION ALL
  SELECT 'linezolid' UNION ALL
  SELECT 'methylene blue' UNION ALL
  SELECT 'granisetron' UNION ALL
  SELECT 'palonosetron' UNION ALL
  SELECT 'tropisetron' UNION ALL
  SELECT 'zolmitriptan' UNION ALL
  SELECT 'naratriptan' UNION ALL
  SELECT 'rizatriptan' UNION ALL
  SELECT 'almotriptan' UNION ALL
  SELECT 'frovatriptan' UNION ALL
  SELECT 'eletriptan' UNION ALL
  SELECT 'methysergide' UNION ALL
  SELECT 'ergotamine' UNION ALL
  SELECT 'dihydroergotamine'
),
cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    p.dod,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age AS age_at_admission,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE a.hadm_id = d.hadm_id
        AND d.icd_version = 10
        AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
    ) THEN 1 ELSE 0 END AS is_hemorrhagic_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age BETWEEN 48 AND 58
),
cohort_with_serotonergic AS (
  SELECT 
    c.*,
    (SELECT COUNT(DISTINCT p.drug)
     FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
     WHERE p.hadm_id = c.hadm_id
       AND p.starttime >= c.admittime
       AND p.starttime <= c.admittime + INTERVAL 48 HOUR
       AND LOWER(p.drug) IN (SELECT LOWER(drug) FROM serotonergic_drugs)
    ) AS num_serotonergic_drugs
  FROM cohort c
),
cohort_with_outcomes AS (
  SELECT 
    *,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    hospital_expire_flag AS mortality
  FROM cohort_with_serotonergic
),
cohort_with_quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY num_serotonergic_drugs) AS quartile
  FROM cohort_with_outcomes
)
SELECT 
  CASE WHEN quartile = 4 THEN 'top_quartile' ELSE 'other' END AS complexity_group,
  AVG(los_days) AS avg_los,
  AVG(mortality) AS mortality_rate
FROM cohort_with_quartiles
GROUP BY complexity_group;