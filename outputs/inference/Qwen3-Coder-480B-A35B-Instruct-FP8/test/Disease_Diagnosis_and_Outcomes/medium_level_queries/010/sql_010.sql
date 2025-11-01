with ami_admissions as (
    -- Identify admissions with primary diagnosis of AMI (I21.x)
    select distinct hadm_id
    from `physionet-data.mimiciv_hosp.diagnoses_icd`
    where icd_version = 10
      and seq_num = 1
      and icd_code like 'I21%'
),
exclusion_diagnoses as (
    -- Identify admissions with shock or respiratory failure
    select distinct hadm_id
    from `physionet-data.mimiciv_hosp.diagnoses_icd`
    where icd_version = 10
      and seq_num > 1
      and (
          icd_code like 'R09.2' or
          icd_code like 'J96%' or
          icd_code like 'J69.0' or
          icd_code like 'J81%' or
          icd_code like 'I50%' or
          icd_code like 'I47.2' or
          icd_code like 'I49.0' or
          icd_code like 'I46%' or
          icd_code like 'I45.6' or
          icd_code like 'I45.92' or
          icd_code like 'I23%'
      )
),
eligible_admissions as (
    -- Admissions with AMI and no exclusion diagnoses
    select a.hadm_id
    from ami_admissions a
    left join exclusion_diagnoses e on a.hadm_id = e.hadm_id
    where e.hadm_id is null
),
patient_info as (
    -- Get patient demographics and filter male 78-88
    select p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
    from `physionet-data.mimiciv_hosp.patients` p
    join `physionet-data.mimiciv_hosp.admissions` a on p.subject_id = a.subject_id
    join eligible_admissions e on a.hadm_id = e.hadm_id
    where p.gender = 'M'
      and p.anchor_age between 78 and 88
),
los_quartiles as (
    -- Compute length of stay and quartiles
    select *,
           date_diff(dischtime, admittime, day) as los_days,
           ntile(4) over (order by date_diff(dischtime, admittime, day)) as los_quartile
    from patient_info
),
comorbidities as (
    -- Count comorbidities (simplified Elixhauser)
    select hadm_id,
           count(*) as comorbidity_count
    from `physionet-data.mimiciv_hosp.diagnoses_icd`
    where seq_num > 1
      and icd_version = 10
      and (
          icd_code like 'I10%' or
          icd_code like 'E10%' or
          icd_code like 'E11%' or
          icd_code like 'N18%' or
          icd_code like 'I25%' or
          icd_code like 'I48%' or
          icd_code like 'J44%' or
          icd_code like 'I27%' or
          icd_code like 'I42%' or
          icd_code like 'G81%' or
          icd_code like 'I63%' or
          icd_code like 'I61%'
      )
    group by hadm_id
),
final_data as (
    select l.*,
           case
               when c.comorbidity_count is null then 'Low'
               when c.comorbidity_count between 1 and 2 then 'Medium'
               else 'High'
           end as comorbidity_burden,
           case when ckd.hadm_id is not null then 1 else 0 end as has_ckd,
           case when dm.hadm_id is not null then 1 else 0 end as has_diabetes
    from los_quartiles l
    left join comorbidities c on l.hadm_id = c.hadm_id
    left join (
        select distinct hadm_id
        from `physionet-data.mimiciv_hosp.diagnoses_icd`
        where icd_version = 10 and icd_code like 'N18%'
    ) ckd on l.hadm_id = ckd.hadm_id
    left join (
        select distinct hadm_id
        from `physionet-data.mimiciv_hosp.diagnoses_icd`
        where icd_version = 10 and (icd_code like 'E10%' or icd_code like 'E11%')
    ) dm on l.hadm_id = dm.hadm_id
)
select
    los_quartile,
    comorbidity_burden,
    count(*) as n_patients,
    avg(cast(hospital_expire_flag as float64)) as mortality_rate,
    avg(cast(has_ckd as float64)) as ckd_prevalence,
    avg(cast(has_diabetes as float64)) as diabetes_prevalence,
    -- Wilson score interval for 95% CI
    safe_divide(
        avg(cast(hospital_expire_flag as float64)) * count(*) + 1.92,
        count(*) + 3.84
    ) - 1.96 * sqrt(
        (avg(cast(hospital_expire_flag as float64)) * (1 - avg(cast(hospital_expire_flag as float64)))) / count(*) + 0.96 / (count(*) + 3.84)
    ) / (count(*) + 3.84) as mortality_lower_ci,
    safe_divide(
        avg(cast(hospital_expire_flag as float64)) * count(*) + 1.92,
        count(*) + 3.84
    ) + 1.96 * sqrt(
        (avg(cast(hospital_expire_flag as float64)) * (1 - avg(cast(hospital_expire_flag as float64)))) / count(*) + 0.96 / (count(*) + 3.84)
    ) / (count(*) + 3.84) as mortality_upper_ci
from final_data
group by los_quartile, comorbidity_burden
order by los_quartile, comorbidity_burden;